require "test_helper"

class GecImportTest < ActiveSupport::TestCase
  test "status predicate helpers match import lifecycle states" do
    gec_import = GecImport.new(status: "pending")
    assert gec_import.queued?
    refute gec_import.completed?
    refute gec_import.failed?

    gec_import.status = "processing"
    assert gec_import.queued?

    gec_import.status = "completed"
    assert gec_import.completed?
    refute gec_import.queued?

    gec_import.status = "failed"
    assert gec_import.failed?
    refute gec_import.queued?
  end
end
