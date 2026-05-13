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
end
