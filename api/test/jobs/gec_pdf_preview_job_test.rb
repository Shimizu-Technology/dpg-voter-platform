require "test_helper"

class GecPdfPreviewJobTest < ActiveSupport::TestCase
  test "marks preview failed when file data was already cleared" do
    user = User.create!(
      clerk_id: "clerk-preview-job-test",
      email: "preview-job-test@example.com",
      role: "campaign_admin"
    )

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-job-test",
      uploaded_by_user: user,
      filename: "preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4 sample"
    )
    preview.update_columns(file_data: nil)

    GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)

    preview.reload
    assert_equal "failed", preview.status
    assert_equal "PDF data is no longer available; please re-upload the file.", preview.error_message
    assert_equal({}, preview.result_data)
  end

  test "marks preview failed when parser raises unexpectedly" do
    user = User.create!(
      clerk_id: "clerk-preview-job-parser-test",
      email: "preview-job-parser-test@example.com",
      role: "campaign_admin"
    )

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-job-parser-test",
      uploaded_by_user: user,
      filename: "preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4 sample"
    )

    fake_parser = Object.new
    fake_parser.define_singleton_method(:parse_preview_sample) { raise StandardError, "parser crashed" }

    deleted_keys = []
    with_singleton_stubs(S3Service, delete: ->(key) { deleted_keys << key; true }) do
      with_singleton_stubs(GecPdfParserService, new: fake_parser) do
        GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)
      end
    end
    preview.reload
    assert_equal "failed", preview.status
    assert_equal "parser crashed", preview.error_message
    assert_equal({}, preview.result_data)
    assert_nil preview.file_data
    assert_empty deleted_keys
  end

  test "downloads preview source from s3 and clears remote key after success" do
    user = User.create!(
      clerk_id: "clerk-preview-job-s3-test",
      email: "preview-job-s3-test@example.com",
      role: "campaign_admin"
    )

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-job-s3-test",
      uploaded_by_user: user,
      filename: "preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_s3_key: "gec-pdf-previews/preview-job-s3-test/source/preview.pdf"
    )

    fake_result = GecPdfParserService::Result.new(
      rows: [ { "name" => "JUAN CRUZ" } ],
      qa: { status: "preview", preview_mode: true },
      warnings: [],
      errors: []
    )
    fake_parser = Object.new
    fake_parser.define_singleton_method(:parse_preview_sample) { fake_result }

    downloaded_keys = []
    deleted_keys = []
    with_singleton_stubs(
      S3Service,
      download_to_io: ->(key, io) do
        downloaded_keys << key
        io.write("%PDF-1.4 sample")
        true
      end,
      delete: ->(key) { deleted_keys << key; true }
    ) do
      with_singleton_stubs(GecPdfParserService, new: fake_parser) do
        GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)
      end
    end

    preview.reload
    assert_equal "completed", preview.status
    assert_nil preview.file_data
    assert_nil preview.file_s3_key
    assert_equal [ "gec-pdf-previews/preview-job-s3-test/source/preview.pdf" ], downloaded_keys
    assert_equal [ "gec-pdf-previews/preview-job-s3-test/source/preview.pdf" ], deleted_keys
    assert_equal "JUAN CRUZ", preview.result_data["preview_rows"][0]["name"]
  end

  test "deletes s3 preview source when parser raises unexpectedly" do
    user = User.create!(
      clerk_id: "clerk-preview-job-s3-error-test",
      email: "preview-job-s3-error-test@example.com",
      role: "campaign_admin"
    )

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-job-s3-error-test",
      uploaded_by_user: user,
      filename: "preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_s3_key: "gec-pdf-previews/preview-job-s3-error-test/source/preview.pdf"
    )

    fake_parser = Object.new
    fake_parser.define_singleton_method(:parse_preview_sample) { raise StandardError, "parser crashed" }

    downloaded_keys = []
    deleted_keys = []
    with_singleton_stubs(
      S3Service,
      download_to_io: ->(key, io) do
        downloaded_keys << key
        io.write("%PDF-1.4 sample")
        true
      end,
      delete: ->(key) { deleted_keys << key; true }
    ) do
      with_singleton_stubs(GecPdfParserService, new: fake_parser) do
        GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)
      end
    end

    preview.reload
    assert_equal "failed", preview.status
    assert_equal "parser crashed", preview.error_message
    assert_nil preview.file_s3_key
    assert_equal [ "gec-pdf-previews/preview-job-s3-error-test/source/preview.pdf" ], downloaded_keys
    assert_equal [ "gec-pdf-previews/preview-job-s3-error-test/source/preview.pdf" ], deleted_keys
  end

  test "preserves original parser error when finalize fails during rescue" do
    user = User.create!(
      clerk_id: "clerk-preview-job-finalize-failure-test",
      email: "preview-job-finalize-failure-test@example.com",
      role: "campaign_admin"
    )

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-job-finalize-failure-test",
      uploaded_by_user: user,
      filename: "preview.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4 sample"
    )

    fake_parser = Object.new
    fake_parser.define_singleton_method(:parse_preview_sample) { raise StandardError, "parser crashed" }

    original_update = preview.method(:update!)
    preview.define_singleton_method(:update!) do |*args, **kwargs|
      attributes = args.first.is_a?(Hash) ? args.first : kwargs
      if attributes[:status] == "failed"
        raise ActiveRecord::ActiveRecordError, "db write failed"
      end

      original_update.call(*args, **kwargs)
    end

    error = assert_raises(StandardError) do
      with_singleton_stubs(GecPdfPreview, find_by: preview) do
        with_singleton_stubs(GecPdfParserService, new: fake_parser) do
          GecPdfPreviewJob.new.perform(gec_pdf_preview_id: preview.id)
        end
      end
    end

    assert_equal "parser crashed", error.message
  end

  private

  def with_singleton_stubs(klass, stubs)
    singleton = class << klass; self; end
    originals = {}

    stubs.each do |method_name, replacement|
      originals[method_name] = singleton.instance_method(method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name) do |*args, **kwargs, &block|
        if replacement.respond_to?(:call)
          replacement.call(*args, **kwargs, &block)
        else
          replacement
        end
      end
    end

    yield
  ensure
    stubs.each_key do |method_name|
      singleton.send(:remove_method, method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name, originals[method_name]) if originals[method_name]
    end
  end
end
