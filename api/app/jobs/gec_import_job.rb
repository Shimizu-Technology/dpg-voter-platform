# frozen_string_literal: true

require "fileutils"

class GecImportJob < ApplicationJob
  queue_as :default

  def perform(gec_import_id:, upload_id:, gec_list_date:, uploaded_by_user_id: nil, sheet_name: nil, import_type: "full_list", confirm_review: false)
    gec_import = GecImport.find_by(id: gec_import_id)
    upload = GecImportUpload.find_by(id: upload_id)
    return unless gec_import

    unless upload
      fail_import_safely!(gec_import, "Missing upload payload", gec_import_id)
      return
    end

    user = uploaded_by_user_id.present? ? User.find_by(id: uploaded_by_user_id) : nil
    source_tmp = nil
    csv_tempfile = nil

    begin
      gec_import.update!(
        status: "processing",
        metadata: (gec_import.metadata || {}).merge({
          "stage" => "parsing",
          "progress_percent" => 5,
          "started_at" => Time.current.iso8601,
          "active_job_id" => job_id
        })
      )

      upload_is_pdf = pdf_upload?(upload)
      source_tmp = Tempfile.new([ "gec_import_source", upload_is_pdf ? ".pdf" : safe_upload_extension(upload) ])
      source_tmp.binmode
      write_upload_to_tempfile!(upload, source_tmp)
      source_tmp.flush
      source_tmp.close
      preserve_raw_upload!(gec_import, upload)

      service_file_path = source_tmp.path
      artifact_filename = upload.filename.to_s
      artifact_content_type = upload.content_type.presence || "application/octet-stream"
      pdf_qa = nil
      pdf_warnings = []

      if upload_is_pdf
        merge_metadata!(gec_import, stage: "validating_pdf", progress_percent: 10)
        parser = GecPdfParserService.new(file_path: source_tmp.path)
        parsed = parser.parse
        raise "PDF parsing failed: #{parsed.errors.first}" if parsed.errors.any?

        pdf_qa = parsed.qa || {}
        pdf_warnings = parsed.warnings
        raise "PDF QA failed. Please review parsing quality before importing." if pdf_qa[:status] == "fail"
        raise "PDF QA is in review status. Confirm review before importing." if pdf_qa[:status] == "review" && !confirm_review

        merge_metadata!(gec_import, stage: "normalizing_pdf", progress_percent: 35, pdf_qa: pdf_qa, pdf_warnings: pdf_warnings)
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

      result = service.call
      raise result.errors.first unless result.success

      preserve_import_artifact!(result.gec_import, file_path: service_file_path, filename: artifact_filename, content_type: artifact_content_type)
      merge_metadata!(result.gec_import, pdf_qa: pdf_qa, pdf_warnings: pdf_warnings) if pdf_qa.present? || pdf_warnings.any?
      result.gec_import.reload.update!(
        status: "completed",
        metadata: (result.gec_import.metadata || {}).merge({ "stage" => "completed", "progress_percent" => 100 })
      )
      write_audit_log!(result.gec_import, user, result.stats, gec_list_date, import_type)
    rescue StandardError => e
      fail_import_safely!(gec_import, e.message, gec_import_id)
      Rails.logger.error("GecImportJob failed for import #{gec_import_id}: #{e.class}: #{e.message}")
    ensure
      source_tmp&.close!
      csv_tempfile&.close!
      upload&.destroy
    end
  end

  private

  def pdf_upload?(upload)
    upload.content_type.to_s.include?("pdf") || File.extname(upload.filename.to_s).casecmp(".pdf").zero?
  end

  def safe_upload_extension(upload)
    ext = File.extname(upload.filename.to_s).downcase
    %w[.csv .xls .xlsx].include?(ext) ? ext : ".xlsx"
  end

  def write_upload_to_tempfile!(upload, tempfile)
    if upload.file_data.present?
      tempfile.write(upload.file_data)
      return
    end

    raise "Missing upload payload" if upload.file_s3_key.blank?
    raise "Could not download upload payload" unless S3Service.download_to_io(upload.file_s3_key, tempfile)
  end

  def merge_metadata!(gec_import, **attrs)
    gec_import.update!(metadata: (gec_import.metadata || {}).merge(attrs.compact.stringify_keys))
  end

  def fail_import!(gec_import, message)
    gec_import.update!(
      status: "failed",
      metadata: (gec_import.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => message })
    )
  end

  def fail_import_safely!(gec_import, message, import_id)
    fail_import!(gec_import, message)
    true
  rescue StandardError => e
    Rails.logger.error("GecImportJob could not mark import #{import_id} as failed: #{e.class}: #{e.message}")
    false
  end

  def preserve_import_artifact!(gec_import, file_path:, filename:, content_type:)
    safe_filename = S3Service.safe_filename(filename, fallback: "import_artifact")

    unless S3Service.enabled?
      local_dir = Rails.root.join("tmp", "gec_import_artifacts", gec_import.id.to_s)
      FileUtils.mkdir_p(local_dir)
      local_path = local_dir.join(safe_filename)
      FileUtils.cp(file_path, local_path)
      gec_import.update_columns(
        original_file_s3_key: "local://tmp/gec_import_artifacts/#{gec_import.id}/#{safe_filename}",
        original_filename: filename,
        original_content_type: content_type
      )
      return
    end

    s3_key = "gec-imports/#{gec_import.id}/artifact/#{safe_filename}"
    uploaded = File.open(file_path, "rb") { |io| S3Service.upload(s3_key, io, content_type: content_type) }
    return unless uploaded

    gec_import.update_columns(
      original_file_s3_key: s3_key,
      original_filename: filename,
      original_content_type: content_type
    )
  rescue StandardError => e
    Rails.logger.warn("GecImportJob #{gec_import.id}: import artifact preservation failed: #{e.class}: #{e.message}")
  end

  def preserve_raw_upload!(gec_import, upload)
    filename = File.basename(upload.filename.to_s.presence || "gec-import-upload")
    content_type = upload.content_type.presence || "application/octet-stream"

    if upload.file_s3_key.present?
      gec_import.update_columns(
        raw_file_s3_key: upload.file_s3_key,
        raw_filename: filename,
        raw_content_type: content_type
      )
      return
    end

    return unless S3Service.enabled?

    safe_filename = S3Service.safe_filename(filename, fallback: "gec-import-upload")
    s3_key = "gec-imports/#{gec_import.id}/raw/#{safe_filename}"
    uploaded = S3Service.upload(s3_key, StringIO.new(upload.file_data), content_type: content_type)
    return unless uploaded

    gec_import.update_columns(
      raw_file_s3_key: s3_key,
      raw_filename: filename,
      raw_content_type: content_type
    )
  rescue StandardError => e
    Rails.logger.warn("GecImportJob #{gec_import.id}: raw upload preservation failed: #{e.class}: #{e.message}")
  end

  def write_audit_log!(gec_import, user, stats, gec_list_date, import_type)
    AuditLog.create!(
      auditable: gec_import,
      actor_user: user,
      action: "gec_import",
      changed_data: stats,
      metadata: {
        entry_mode: "background_import_job",
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
