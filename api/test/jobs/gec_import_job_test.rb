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
end
