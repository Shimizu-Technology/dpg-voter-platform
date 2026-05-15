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

  test "fails stale queued imports without a live heartbeat" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters.csv",
      import_type: "full_list",
      status: "pending",
      metadata: { "stage" => "queued", "progress_percent" => 0 },
      updated_at: 3.hours.ago
    )

    GecImport.fail_stale_queued!(stale_after: 2.hours)

    gec_import.reload
    assert_equal "failed", gec_import.status
    assert_equal "failed", gec_import.metadata["stage"]
    assert_equal 100, gec_import.metadata["progress_percent"]
    assert_match "no active worker heartbeat", gec_import.metadata["error"]
  end

  test "keeps stale-looking imports when a live heartbeat exists" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters.csv",
      import_type: "full_list",
      status: "processing",
      metadata: { "stage" => "importing", "progress_percent" => 65 },
      updated_at: 3.hours.ago
    )
    cache = Rails.cache
    original_read = cache.method(:read)
    cache.define_singleton_method(:read) do |key, *args, **kwargs|
      key == "gec_import_heartbeat:#{gec_import.id}" ? 5.minutes.ago.iso8601 : original_read.call(key, *args, **kwargs)
    end

    GecImport.fail_stale_queued!(stale_after: 2.hours)

    assert_equal "processing", gec_import.reload.status
  ensure
    Rails.cache.define_singleton_method(:read, original_read) if original_read
  end
end
