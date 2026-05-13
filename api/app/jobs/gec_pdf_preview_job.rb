# frozen_string_literal: true

class GecPdfPreviewJob < ApplicationJob
  queue_as :default

  def perform(gec_pdf_preview_id:)
    preview = GecPdfPreview.find_by(id: gec_pdf_preview_id)
    return unless preview
    return if preview.completed? || preview.failed?

    source_s3_key = preview.file_s3_key.presence
    temp = Tempfile.new([ "gec_pdf_preview", ".pdf" ])
    temp.binmode

    preview.update!(status: "processing", error_message: nil)

    unless write_source_to_tempfile(preview, temp, source_s3_key)
      finalize_preview!(
        preview,
        status: "failed",
        error_message: "PDF data is no longer available; please re-upload the file.",
        result_data: {},
        source_s3_key: source_s3_key
      )
      return
    end

    parsed = GecPdfParserService.new(file_path: temp.path).parse_preview_sample

    if parsed.errors.any?
      finalize_preview!(
        preview,
        status: "failed",
        error_message: parsed.errors.first,
        result_data: {},
        source_s3_key: source_s3_key
      )
      return
    end

    finalize_preview!(
      preview,
      status: "completed",
      error_message: nil,
      result_data: {
        "qa" => parsed.qa,
        "warnings" => parsed.warnings,
        "row_count" => parsed.rows.size,
        "preview_rows" => parsed.rows.first(100)
      },
      source_s3_key: source_s3_key
    )
  rescue StandardError => e
    begin
      finalize_preview!(
        preview,
        status: "failed",
        error_message: e.message,
        result_data: {},
        source_s3_key: source_s3_key || preview&.file_s3_key.presence
      ) unless preview&.completed? || preview&.failed?
    rescue StandardError => finalize_error
      Rails.logger.warn(
        "GecPdfPreviewJob preview #{preview&.id}: failed to persist terminal state after #{e.class}: #{e.message}: " \
        "#{finalize_error.class}: #{finalize_error.message}"
      )
    end
    raise e
  ensure
    temp&.close!
  end

  private

  def finalize_preview!(preview, status:, error_message:, result_data:, source_s3_key:)
    preview.update!(
      status: status,
      error_message: error_message,
      result_data: result_data,
      file_data: nil
    )
    cleanup_preview_source!(preview, source_s3_key)
  end

  def write_source_to_tempfile(preview, tempfile, source_s3_key)
    if preview.file_data.present?
      tempfile.write(preview.file_data)
      tempfile.flush
      return true
    end

    return false if source_s3_key.blank?

    streamed = S3Service.download_to_io(source_s3_key, tempfile)
    tempfile.flush if streamed
    streamed
  end

  def cleanup_preview_source!(preview, source_s3_key)
    return if preview.blank? || source_s3_key.blank?

    deleted = S3Service.delete(source_s3_key)
    preview.update_column(:file_s3_key, nil) if deleted
  rescue StandardError => e
    Rails.logger.warn("GecPdfPreviewJob preview #{preview.id}: failed to delete preview source #{source_s3_key}: #{e.class}: #{e.message}")
  end
end
