require "test_helper"

class GecImportJobTest < ActiveSupport::TestCase
  test "failure recording does not re-raise when the status update fails" do
    gec_import = GecImport.create!(
      filename: "gec-import.pdf",
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list",
      status: "processing"
    )
    original_fail_import = GecImportJob.instance_method(:fail_import!)
    GecImportJob.define_method(:fail_import!) do |_import, _message|
      raise ActiveRecord::StatementInvalid, "database temporarily unavailable"
    end

    assert_nothing_raised do
      GecImportJob.new.send(:fail_import_safely!, gec_import, "PDF parsing failed", gec_import.id)
    end
  ensure
    GecImportJob.define_method(:fail_import!, original_fail_import) if original_fail_import
  end

  test "preserves import artifact locally when S3 is disabled" do
    gec_import = GecImport.create!(
      filename: "gec-import.csv",
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list",
      status: "processing"
    )
    artifact = Tempfile.new([ "gec-import-artifact", ".csv" ])
    artifact.write("Reg No.,Last Name,First Name\n1,Cruz,Juan\n")
    artifact.flush

    original_s3_enabled = S3Service.method(:enabled?)
    S3Service.define_singleton_method(:enabled?) { false }

    GecImportJob.new.send(
      :preserve_import_artifact!,
      gec_import,
      file_path: artifact.path,
      filename: "gec-import.csv",
      content_type: "text/csv"
    )

    gec_import.reload
    assert_match %r{\Alocal://tmp/gec_import_artifacts/#{gec_import.id}/}, gec_import.original_file_s3_key
    assert_equal "gec-import.csv", gec_import.original_filename
    assert File.exist?(Rails.root.join(gec_import.original_file_s3_key.delete_prefix("local://")))
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    artifact&.close!
    FileUtils.rm_rf(Rails.root.join("tmp", "gec_import_artifacts", gec_import.id.to_s)) if defined?(gec_import) && gec_import&.id
  end

  test "writes S3 upload payloads to the import tempfile" do
    gec_import = GecImport.create!(
      filename: "gec-import.csv",
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list",
      status: "processing"
    )
    upload = GecImportUpload.create!(
      gec_import: gec_import,
      filename: "gec-import.pdf",
      content_type: "application/pdf",
      file_s3_key: "gec-imports/#{gec_import.id}/raw/gec-import.pdf"
    )
    tempfile = Tempfile.new([ "gec-import-source", ".pdf" ])
    tempfile.binmode

    original_download_to_io = S3Service.method(:download_to_io)
    S3Service.define_singleton_method(:download_to_io) do |key, io|
      io.write("downloaded #{key}")
      true
    end

    GecImportJob.new.send(:write_upload_to_tempfile!, upload, tempfile)
    tempfile.rewind

    assert_equal "downloaded gec-imports/#{gec_import.id}/raw/gec-import.pdf", tempfile.read
  ensure
    S3Service.define_singleton_method(:download_to_io, original_download_to_io) if original_download_to_io
    tempfile&.close!
  end

  test "preserves an existing S3 upload as the raw import file" do
    gec_import = GecImport.create!(
      filename: "gec-import.csv",
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list",
      status: "processing"
    )
    upload = GecImportUpload.create!(
      gec_import: gec_import,
      filename: "gec-import.pdf",
      content_type: "application/pdf",
      file_s3_key: "gec-imports/#{gec_import.id}/raw/gec-import.pdf"
    )

    GecImportJob.new.send(:preserve_raw_upload!, gec_import, upload)

    gec_import.reload
    assert_equal upload.file_s3_key, gec_import.raw_file_s3_key
    assert_equal "gec-import.pdf", gec_import.raw_filename
    assert_equal "application/pdf", gec_import.raw_content_type
  end
end
