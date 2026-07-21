# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260721100000_backfill_legacy_poll_watcher_precinct_assignments")

class BackfillLegacyPollWatcherPrecinctAssignmentsTest < ActiveSupport::TestCase
  test "backfills active precincts for village-only poll watchers" do
    village = Village.create!(name: "Legacy Poll Watcher Village")
    active_precinct = Precinct.create!(number: "L-1", village: village, active: true)
    inactive_precinct = Precinct.create!(number: "L-2", village: village, active: false)
    watcher = User.create!(
      clerk_id: "legacy-village-poll-watcher",
      email: "legacy-village-poll-watcher@example.com",
      role: "poll_watcher",
      assigned_village_id: village.id
    )

    BackfillLegacyPollWatcherPrecinctAssignments.new.migrate(:up)

    assert_equal [ active_precinct.id ], watcher.assigned_poll_watcher_precincts.reload.pluck(:id)
    assert_not_includes watcher.assigned_poll_watcher_precincts, inactive_precinct
  end

  test "does not expand a poll watcher who already has an exact assignment" do
    village = Village.create!(name: "Exact Poll Watcher Village")
    assigned_precinct = Precinct.create!(number: "E-1", village: village)
    other_precinct = Precinct.create!(number: "E-2", village: village)
    watcher = User.create!(
      clerk_id: "exact-precinct-poll-watcher",
      email: "exact-precinct-poll-watcher@example.com",
      role: "poll_watcher",
      assigned_village_id: village.id
    )
    PollWatcherPrecinctAssignment.create!(user: watcher, precinct: assigned_precinct)

    BackfillLegacyPollWatcherPrecinctAssignments.new.migrate(:up)

    assert_equal [ assigned_precinct.id ], watcher.assigned_poll_watcher_precincts.reload.pluck(:id)
    assert_not_includes watcher.assigned_poll_watcher_precincts, other_precinct
  end
end
