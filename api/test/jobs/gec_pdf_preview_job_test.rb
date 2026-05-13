require "test_helper"

class GecPdfPreviewJobTest < ActiveSupport::TestCase
  test "marks preview failed when processing raises after status update" do
    user = User.create!(
      clerk_id: "clerk-gec-preview-job",
      email: "gec-preview-job@example.com",
      name: "GEC Preview Job User",
      role: "campaign_admin"
    )
    preview = GecPdfPreview.create!(
      preview_request_id: "processing-failure-preview",
      uploaded_by_user: user,
      filename: "gec-preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4\n%%EOF\n"
    )
    original_write_source = GecPdfPreviewJob.instance_method(:write_source_to_tempfile)
    GecPdfPreviewJob.define_method(:write_source_to_tempfile) do |_preview, _tempfile, _source_s3_key|
      raise "processor exploded"
    end

    begin
      GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)
    ensure
      GecPdfPreviewJob.define_method(:write_source_to_tempfile, original_write_source)
    end

    preview.reload
    assert_equal "failed", preview.status
    assert_match "processor exploded", preview.error_message
    assert_nil preview.file_data
  end
end
