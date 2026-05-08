# frozen_string_literal: true

require "socket"

class GecImportJob < ApplicationJob
  queue_as :default

  # Advisory lock keys for GEC imports (2-key form for portability).
  # Convention: key1 = subsystem ID (81 = GEC), key2 = operation (1 = import).
  # These are application-global PostgreSQL advisory locks. If you add other
  # advisory locks elsewhere in this codebase, choose different key1/key2
  # values to avoid collisions. See: db/advisory_lock_registry.md
  IMPORT_LOCK_KEY_1 = 81
  IMPORT_LOCK_KEY_2 = 1
  # 20 retries with exponential backoff (30s, 60s, 120s, ..., capped at 5 min)
  # gives ~30+ minutes total wait — enough for a full 60K-row import to finish.
  MAX_IMPORT_REQUEUE_ATTEMPTS = 20

  # If a "processing" import hasn't been updated in this long, treat it as
  # stale (crashed worker / OOM-kill / pod eviction). A retry can then
  # reclaim the import instead of bailing out at the guard check.
  PROCESSING_TIMEOUT = 30.minutes

  # OPERATOR NOTE: If the only outstanding job crashes and the queue backend
  # exhausts its retries before PROCESSING_TIMEOUT elapses, no retry will
  # exist to reclaim the import and it will be stuck in "processing" until
  # manual intervention. Configure job retries with a window of at least
  # PROCESSING_TIMEOUT + GecImportService::IMPORT_CACHE_TTL (currently
  # 30 min + 90 min = 2 hours) to ensure recovery is possible.

  # Process-level mutex to prevent concurrent imports within the same multi-threaded
  # worker (e.g. Sidekiq). pg_try_advisory_lock is session-level and each thread gets
  # its own DB connection, so two threads in the same process could both acquire the
  # lock. This mutex gates access before the DB lock for belt-and-suspenders safety.
  IMPORT_MUTEX = Mutex.new

  def perform(gec_import_id:, upload_id:, gec_list_date:, uploaded_by_user_id: nil, sheet_name: nil, import_type: "full_list", confirm_review: false)
    gec_import = GecImport.find_by(id: gec_import_id)
    # Load metadata only (no file_data blob) for guard checks and lock contention path.
    # The full blob is loaded only after both locks are acquired to avoid holding
    # 10-50 MB in Ruby heap while waiting for requeue.
    upload_meta = GecImportUpload.where(id: upload_id).select(:id, :gec_import_id, :filename, :content_type).first

    # Allow retries of stale "processing" imports. A running job writes a
    # heartbeat to Rails.cache every 5,000 rows + at each stage transition.
    # The DB updated_at is invisible during the open transaction, so we
    # check the cache heartbeat first. If neither has been refreshed in
    # PROCESSING_TIMEOUT, the job is assumed crashed and we allow a retry.
    stale_processing = if gec_import&.status == "processing"
      cached_heartbeat = begin
        Rails.cache.read("gec_import_heartbeat:#{gec_import.id}")
      rescue StandardError
        nil
      end
      last_seen = if cached_heartbeat.present?
        begin
          Time.parse(cached_heartbeat)
        rescue ArgumentError
          gec_import.updated_at
        end
      else
        gec_import.updated_at
      end
      last_seen < PROCESSING_TIMEOUT.ago
    else
      false
    end

    # Terminal states: safe to clean up upload and bail.
    if gec_import.nil? || %w[completed failed].include?(gec_import.status)
      GecImportUpload.where(id: upload_id).delete_all
      return
    end

    # Non-stale processing: a healthy job is already running and still
    # holds the tempfile. Do NOT delete the upload — the running job
    # may crash later and a retry would need it for recovery.
    #
    # Edge case: if this is the last retry and the running job later
    # crashes, no future job will arrive to reclaim the import. It will
    # stay in "processing" until manual intervention. This is acceptable
    # because the alternative (deleting the upload) makes recovery
    # impossible. See HEARTBEAT_TTL comment for queue retry window
    # requirements.
    if gec_import.status == "processing" && !stale_processing
      return
    end

    unless upload_meta
      gec_import.update!(
        status: "failed",
        metadata: (gec_import.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => "Missing upload payload" })
      )
      return
    end

    user = uploaded_by_user_id.present? ? User.find_by(id: uploaded_by_user_id) : nil
    worker_host = Socket.gethostname rescue "unknown"
    source_tmp = nil
    csv_tempfile = nil
    source_tmp_file_path = nil
    lock_acquired = false
    advisory_lock_connection = nil
    advisory_lock_backend_pid = nil
    mutex_acquired = false
    should_destroy_upload = true

    begin
      Rails.logger.info(
        "GecImportJob start import=#{gec_import_id} job_id=#{job_id} upload_id=#{upload_id} " \
        "import_type=#{import_type} filename=#{upload_meta&.filename} worker_host=#{worker_host}"
      )

      # Layer 1: Process-level mutex (protects against multi-threaded workers like Sidekiq)
      mutex_acquired = IMPORT_MUTEX.try_lock
      unless mutex_acquired
        requeued = handle_lock_contention(gec_import, gec_import_id, upload_id, gec_list_date, uploaded_by_user_id, sheet_name, import_type, confirm_review)
        should_destroy_upload = !requeued # destroy upload if permanently failed
        return
      end

      # Layer 2: DB advisory lock — only needed for full_list imports which call
      # detect_purged_voters and require global voter-state serialization.
      # changes_only imports do row-level upserts without purge detection, so
      # fully serializing them behind the same lock is unnecessarily conservative.
      if import_type == "full_list"
        advisory_lock_connection = ActiveRecord::Base.connection
        advisory_lock_backend_pid = advisory_lock_connection.raw_connection.backend_pid
        lock_result = advisory_lock_connection.select_value("SELECT pg_try_advisory_lock(#{IMPORT_LOCK_KEY_1}, #{IMPORT_LOCK_KEY_2})")
        lock_acquired = ActiveModel::Type::Boolean.new.cast(lock_result)
        unless lock_acquired
          requeued = handle_lock_contention(gec_import, gec_import_id, upload_id, gec_list_date, uploaded_by_user_id, sheet_name, import_type, confirm_review)
          should_destroy_upload = !requeued
          return
        end
      end

      gec_import.update!(
        status: "processing",
        metadata: (gec_import.metadata || {}).merge({
          "stage" => "parsing",
          "progress_percent" => 5,
          "active_job_id" => job_id,
          "queue_backend" => Rails.application.config.active_job.queue_adapter.to_s,
          "started_at" => Time.current.iso8601,
          "worker_host" => worker_host,
          "worker_pid" => Process.pid
        })
      )

      # Now load the full binary blob — only after both locks are held.
      Rails.logger.info("GecImportJob import=#{gec_import_id} loading upload payload upload_id=#{upload_id}")
      upload = GecImportUpload.find(upload_id)

      upload_is_pdf = pdf_upload?(upload)
      Rails.logger.info("GecImportJob import=#{gec_import_id} materializing source tempfile pdf=#{upload_is_pdf}")
      source_tmp = Tempfile.new([ "gec_import_source", upload_is_pdf ? ".pdf" : safe_upload_extension(upload) ])
      source_tmp.binmode
      source_tmp.write(upload.file_data)
      source_tmp.flush
      source_tmp_file_path = source_tmp.path
      source_tmp.close

      artifact_filename = upload.filename.to_s
      artifact_content_type = upload.content_type || "application/octet-stream"
      service_file_path = source_tmp_file_path
      pdf_qa = nil
      pdf_warnings = []

      if upload_is_pdf
        Rails.logger.info("GecImportJob import=#{gec_import_id} starting PDF normalization")
        merge_metadata!(gec_import, stage: "validating_pdf", progress_percent: 10)

        last_reported_page = -1
        parser = GecPdfParserService.new(
          file_path: source_tmp_file_path,
          progress_callback: lambda do |pages_processed:, page_count:|
            next if page_count.to_i <= 0
            next if pages_processed == last_reported_page
            next unless pages_processed.zero? || pages_processed == page_count || (pages_processed % 10).zero?

            last_reported_page = pages_processed
            percent = 10 + ((pages_processed.to_f / page_count) * 20).to_i
            write_progress_cache(
              gec_import.id,
              stage: "validating_pdf",
              progress_percent: [ percent, 30 ].min,
              pages_processed: pages_processed,
              page_count: page_count
            )
          end
        )
        parsed = parser.parse
        raise "PDF parsing failed: #{parsed.errors.first}" if parsed.errors.any?

        pdf_qa = parsed.qa || {}
        pdf_warnings = parsed.warnings

        if pdf_qa[:status] == "fail"
          raise "PDF QA failed. Please review parsing quality before importing."
        end

        if pdf_qa[:status] == "review" && !confirm_review
          raise "PDF QA is in review status. Confirm review before importing."
        end

        merge_metadata!(
          gec_import,
          stage: "normalizing_pdf",
          progress_percent: 35,
          pdf_qa: pdf_qa,
          pdf_warnings: pdf_warnings,
          pages_processed: pdf_qa[:page_count],
          page_count: pdf_qa[:page_count]
        )

        csv_tempfile = parser.write_normalized_csv(parsed.rows)
        service_file_path = csv_tempfile.path
        artifact_filename = "#{File.basename(upload.filename.to_s, ".*")}.csv"
        artifact_content_type = "text/csv"
      end

      service = GecImportService.new(
        file_path: service_file_path,
        gec_list_date: Date.parse(gec_list_date),
        uploaded_by_user: user,
        sheet_name: sheet_name,
        import_type: import_type,
        gec_import: gec_import,
        parsing_progress_percent: upload_is_pdf ? 40 : 10,
        importing_progress_start: upload_is_pdf ? 45 : 20,
        importing_progress_end: 85,
        re_vetting_progress_percent: 90
      )

      Rails.logger.info("GecImportJob import=#{gec_import_id} invoking import service file_path=#{service_file_path}")
      result = service.call

      unless result.success
        Rails.logger.error("GecImportJob: service returned failure for import ##{gec_import_id}: #{result.errors.first}")
      end

      if result.success
        Rails.logger.info("GecImportJob import=#{gec_import_id} completed successfully stats=#{result.stats.inspect}")
        preserve_import_artifact!(
          gec_import,
          file_path: service_file_path,
          filename: artifact_filename,
          content_type: artifact_content_type
        )

        merge_metadata!(result.gec_import, pdf_qa: pdf_qa, pdf_warnings: pdf_warnings) if pdf_qa.present? || pdf_warnings.any?
        result.gec_import.reload
        result.gec_import.update!(
          status: "completed",
          metadata: (result.gec_import.metadata || {}).merge({
            "stage" => "completed",
            "progress_percent" => 100
          })
        )

        begin
          AuditLog.create(
            auditable: result.gec_import,
            auditable_type: result.gec_import.class.name,
            actor_user: user,
            action: "gec_import",
            changed_data: result.stats,
            metadata: {
              entry_mode: "background_import_job",
              context: "background_job",
              request_context_available: false,
              source: "gec_import_job",
              uploaded_by_user_id: user&.id,
              uploaded_by_user_email: user&.email,
              import_type: import_type,
              gec_list_date: gec_list_date
            }
          )
        rescue StandardError => e
          Rails.logger.warn("Background import audit log failed for #{gec_import.id}: #{e.message}")
        end
      end
    rescue StandardError => e
      gec_import&.update!(
        status: "failed",
        metadata: (gec_import&.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => e.message })
      )
      Rails.logger.error("GecImportJob failed for #{gec_import_id} job_id=#{job_id}: #{e.class}: #{e.message}")
    ensure
      source_tmp&.close!
      csv_tempfile&.close!
      GecImportUpload.where(id: upload_id).delete_all if should_destroy_upload
      if lock_acquired
        begin
          current_backend_pid = advisory_lock_connection&.raw_connection&.backend_pid
          if current_backend_pid == advisory_lock_backend_pid
            advisory_lock_connection.execute("SELECT pg_advisory_unlock(#{IMPORT_LOCK_KEY_1}, #{IMPORT_LOCK_KEY_2})")
          else
            Rails.logger.info(
              "GecImportJob #{gec_import_id}: skipped advisory unlock because DB session changed " \
              "(expected_backend_pid=#{advisory_lock_backend_pid.inspect} current_backend_pid=#{current_backend_pid.inspect})"
            )
          end
        rescue StandardError => e
          Rails.logger.warn("GecImportJob #{gec_import_id}: advisory unlock failed: #{e.class}: #{e.message}")
        end
      end
      IMPORT_MUTEX.unlock if mutex_acquired
    end
  end

  private

  # Returns true if job was re-queued (upload still needed), false if permanently failed (upload can be cleaned up).
  def handle_lock_contention(gec_import, gec_import_id, upload_id, gec_list_date, uploaded_by_user_id, sheet_name, import_type, confirm_review)
    requeue_count = (gec_import.metadata || {})["requeue_count"].to_i
    if requeue_count >= MAX_IMPORT_REQUEUE_ATTEMPTS
      gec_import.update!(
        status: "failed",
        metadata: (gec_import.metadata || {}).merge({
          "stage" => "failed",
          "progress_percent" => 100,
          "error" => "Exceeded import lock requeue limit (#{MAX_IMPORT_REQUEUE_ATTEMPTS})"
        })
      )
      return false # permanently done — caller should clean up upload
    end

    wait_seconds = [ 30 * (2**requeue_count), 300 ].min # exponential backoff, capped at 5 minutes
    Rails.logger.warn("GecImportJob #{gec_import_id}: import lock busy for #{import_type}, retrying in #{wait_seconds}s (#{requeue_count + 1}/#{MAX_IMPORT_REQUEUE_ATTEMPTS})")
    gec_import.update!(
      status: "pending",
      metadata: (gec_import.metadata || {}).merge({
        "stage" => "queued",
        "progress_percent" => 0,
        "note" => "Waiting for another import to finish (retry #{requeue_count + 1}/#{MAX_IMPORT_REQUEUE_ATTEMPTS})",
        "requeue_count" => requeue_count + 1
      })
    )
    self.class.set(wait: wait_seconds.seconds).perform_later(
      gec_import_id: gec_import_id,
      upload_id: upload_id,
      gec_list_date: gec_list_date,
      uploaded_by_user_id: uploaded_by_user_id,
      sheet_name: sheet_name,
      import_type: import_type,
      confirm_review: confirm_review
    )
    true # re-queued — upload still needed
  end

  def pdf_upload?(upload)
    upload.content_type.to_s.start_with?("application/pdf") || File.extname(upload.filename.to_s).casecmp(".pdf").zero?
  end

  def safe_upload_extension(upload)
    raw_ext = File.extname(upload.filename.to_s).downcase
    %w[.xlsx .xls .csv].include?(raw_ext) ? raw_ext : ".xlsx"
  end

  def preserve_import_artifact!(gec_import, file_path:, filename:, content_type:)
    return unless S3Service.enabled?

    safe_filename = S3Service.safe_filename(filename, fallback: "import_artifact")
    s3_key = "gec-imports/#{gec_import.id}/artifact/#{safe_filename}"

    upload_result = File.open(file_path, "rb") do |io|
      S3Service.upload(s3_key, io, content_type: content_type)
    end

    if upload_result
      gec_import.update_columns(
        original_file_s3_key: s3_key,
        original_filename: filename,
        original_content_type: content_type
      )
    else
      Rails.logger.warn("GecImportJob #{gec_import.id}: S3 upload failed, import artifact not preserved")
    end
  end

  def merge_metadata!(gec_import, **attrs)
    gec_import.update!(metadata: (gec_import.metadata || {}).merge(attrs.compact.stringify_keys))
  end

  def write_progress_cache(import_id, stage:, progress_percent:, pages_processed: nil, page_count: nil)
    Rails.cache.write(
      "gec_import_progress:#{import_id}",
      {
        "stage" => stage,
        "progress_percent" => progress_percent,
        "pages_processed" => pages_processed,
        "page_count" => page_count,
        "updated_at" => Time.current.iso8601
      }.compact,
      expires_in: GecImportService::IMPORT_CACHE_TTL
    )
    Rails.cache.write(
      "gec_import_heartbeat:#{import_id}",
      Time.current.iso8601,
      expires_in: GecImportService::IMPORT_CACHE_TTL
    )
  rescue StandardError => e
    Rails.logger.warn("GecImportJob #{import_id}: progress cache write failed: #{e.class}: #{e.message}")
  end
end
