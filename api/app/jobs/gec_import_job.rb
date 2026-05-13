# frozen_string_literal: true

class GecImportJob < ApplicationJob
  queue_as :default

  discard_on StandardError

  def perform(gec_import_id:, upload_id:, gec_list_date:, uploaded_by_user_id: nil, sheet_name: nil, import_type: "full_list", confirm_review: false)
    gec_import = GecImport.find_by(id: gec_import_id)
    upload = GecImportUpload.find_by(id: upload_id)
    return unless gec_import

    unless upload
      fail_import!(gec_import, "Missing upload payload")
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
      source_tmp.write(upload.file_data)
      source_tmp.flush
      source_tmp.close

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
      fail_import!(gec_import, e.message)
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

  def merge_metadata!(gec_import, **attrs)
    gec_import.update!(metadata: (gec_import.metadata || {}).merge(attrs.compact.stringify_keys))
  end

  def fail_import!(gec_import, message)
    gec_import.update!(
      status: "failed",
      metadata: (gec_import.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => message })
    )
  end

  def preserve_import_artifact!(gec_import, file_path:, filename:, content_type:)
    return unless S3Service.enabled?

    safe_filename = S3Service.safe_filename(filename, fallback: "import_artifact")
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
