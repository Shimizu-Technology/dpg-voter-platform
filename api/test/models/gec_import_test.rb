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

  test "continues failing later stale imports when one stale import errors" do
    first_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters-first.csv",
      import_type: "full_list",
      status: "pending",
      metadata: { "stage" => "queued", "progress_percent" => 0 },
      updated_at: 3.hours.ago
    )
    second_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters-second.csv",
      import_type: "full_list",
      status: "pending",
      metadata: { "stage" => "queued", "progress_percent" => 0 },
      updated_at: 3.hours.ago
    )
    original_fail_as_stale = GecImport.instance_method(:fail_as_stale!)

    GecImport.define_method(:fail_as_stale!) do
      if filename == "gec-voters-first.csv"
        raise ActiveRecord::RecordInvalid, self
      end

      original_fail_as_stale.bind_call(self)
    end

    GecImport.fail_stale_queued!(stale_after: 2.hours)

    assert_equal "pending", first_import.reload.status
    assert_equal "failed", second_import.reload.status
  ensure
    GecImport.define_method(:fail_as_stale!, original_fail_as_stale) if original_fail_as_stale
  end

  test "does not fail imports that are no longer queued" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters.csv",
      import_type: "full_list",
      status: "completed",
      metadata: { "stage" => "completed", "progress_percent" => 100 },
      updated_at: 3.hours.ago
    )

    refute gec_import.fail_as_stale!
    assert_equal "completed", gec_import.reload.status
    assert_equal "completed", gec_import.metadata["stage"]
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

    original_read = Rails.cache.method(:read)
    read_cache = lambda do |key, *args, **kwargs|
      if key == "gec_import_heartbeat:#{gec_import.id}"
        5.minutes.ago.iso8601
      else
        original_read.call(key, *args, **kwargs)
      end
    end

    with_stubbed_singleton_method(Rails.cache, :read, read_cache) do
      GecImport.fail_stale_queued!(stale_after: 2.hours)
    end

    assert_equal "processing", gec_import.reload.status
  end
end
