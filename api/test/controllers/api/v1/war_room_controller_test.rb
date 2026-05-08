require "test_helper"

class Api::V1::WarRoomControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      clerk_id: "clerk-war-room-admin",
      email: "war-room-admin@example.com",
      name: "War Room Admin",
      role: "campaign_admin"
    )
    @watcher = User.create!(
      clerk_id: "clerk-war-room-watcher",
      email: "war-room-watcher@example.com",
      name: "War Room Watcher",
      role: "poll_watcher"
    )

    @village_a = Village.create!(name: "Village A", region: "North")
    @village_b = Village.create!(name: "Village B", region: "South")
    @precinct_a = Precinct.create!(number: "A-1", village: @village_a, registered_voters: 200)
    @precinct_a_hidden = Precinct.create!(number: "A-2", village: @village_a, registered_voters: 150)
    @precinct_b = Precinct.create!(number: "B-1", village: @village_b, registered_voters: 180)
    PollWatcherPrecinctAssignment.create!(user: @watcher, precinct: @precinct_a, assigned_by_user: @admin)
    @active_import = GecImport.create!(
      gec_list_date: Date.current,
      filename: "active-war-room.csv",
      status: "completed",
      import_type: "full_list",
      active_election_day: true
    )

    PollReport.create!(precinct: @precinct_a, voter_count: 60, report_type: "turnout_update", reported_at: Time.current)
    PollReport.create!(precinct: @precinct_a_hidden, voter_count: 40, report_type: "turnout_update", reported_at: Time.current)
    PollReport.create!(precinct: @precinct_b, voter_count: 30, report_type: "turnout_update", reported_at: Time.current)

    @supporter_a1 = Supporter.create!(
      first_name: "Supporter", last_name: "A1", print_name: "Supporter A1",
      contact_number: "6715552101",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @voter_a1 = GecVoter.create!(
      first_name: "Supporter",
      last_name: "A1",
      village: @village_a,
      village_name: @village_a.name,
      precinct: @precinct_a,
      precinct_number: @precinct_a.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @supporter_a1.update!(gec_voter: @voter_a1)
    @supporter_a2 = Supporter.create!(
      first_name: "Supporter", last_name: "A2", print_name: "Supporter A2",
      contact_number: "6715552102",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      turnout_status: "voted"
    )
    @voter_a2 = GecVoter.create!(
      first_name: "Supporter",
      last_name: "A2",
      village: @village_a,
      village_name: @village_a.name,
      precinct: @precinct_a,
      precinct_number: @precinct_a.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "voted"
    )
    @supporter_a2.update!(gec_voter: @voter_a2)
    @supporter_b1 = Supporter.create!(
      first_name: "Supporter", last_name: "B1", print_name: "Supporter B1",
      contact_number: "6715552201",
      village: @village_b,
      precinct: @precinct_b,
      source: "staff_entry",
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @voter_b1 = GecVoter.create!(
      first_name: "Supporter",
      last_name: "B1",
      village: @village_b,
      village_name: @village_b.name,
      precinct: @precinct_b,
      precinct_number: @precinct_b.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @supporter_b1.update!(gec_voter: @voter_b1)
    @supporter_observed = Supporter.create!(
      first_name: "Observed", last_name: "Elsewhere", print_name: "Observed Elsewhere",
      contact_number: "6715552103",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct B-1 (Village B)."
    )
    @voter_observed = GecVoter.create!(
      first_name: "Observed",
      last_name: "Elsewhere",
      village: @village_a,
      village_name: @village_a.name,
      precinct: @precinct_a,
      precinct_number: @precinct_a.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct B-1 (Village B).",
      turnout_updated_at: Time.current,
      turnout_updated_by_user: @admin,
      turnout_source: "poll_watcher"
    )
    @supporter_observed.update!(gec_voter: @voter_observed)
    @old_voter = GecVoter.create!(
      first_name: "Old",
      last_name: "List",
      village: @village_a,
      village_name: @village_a.name,
      precinct: @precinct_a,
      precinct_number: @precinct_a.number,
      gec_list_date: Date.current + 1.day,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @old_supporter = Supporter.create!(
      first_name: "Old", last_name: "List", print_name: "Old List",
      contact_number: "6715552199",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      gec_voter: @old_voter
    )
    @pending_unmatched_supporter = Supporter.create!(
      first_name: "Pending", last_name: "Unmatched", print_name: "Pending Unmatched",
      contact_number: "6715552197",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      review_status: "rejected",
      verification_status: "unverified"
    )
    @unmatched_supporter = Supporter.create!(
      first_name: "Unmatched", last_name: "Supporter", print_name: "Unmatched Supporter",
      contact_number: "6715552198",
      village: @village_a,
      precinct: @precinct_a,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified"
    )
    @hidden_supporter = Supporter.create!(
      first_name: "Hidden", last_name: "Supporter", print_name: "Hidden Supporter",
      contact_number: "6715552196",
      village: @village_a,
      precinct: @precinct_a_hidden,
      source: "staff_entry",
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @hidden_voter = GecVoter.create!(
      first_name: "Hidden",
      last_name: "Supporter",
      village: @village_a,
      village_name: @village_a.name,
      precinct: @precinct_a_hidden,
      precinct_number: @precinct_a_hidden.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @hidden_supporter.update!(gec_voter: @hidden_voter)

    SupporterContactAttempt.create!(
      supporter: @supporter_a1,
      recorded_by_user: @admin,
      outcome: "attempted",
      channel: "call",
      recorded_at: Time.current
    )
    SupporterContactAttempt.create!(
      supporter: @supporter_b1,
      recorded_by_user: @admin,
      outcome: "reached",
      channel: "call",
      recorded_at: Time.current
    )
    SupporterContactAttempt.create!(
      supporter: @hidden_supporter,
      recorded_by_user: @admin,
      outcome: "reached",
      channel: "call",
      recorded_at: Time.current
    )
  end

  test "returns war room queue and outreach metrics" do
    get "/api/v1/war_room", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal 3, payload.dig("stats", "total_not_yet_voted")
    assert_equal 1, payload.dig("stats", "total_observed_elsewhere")
    assert_equal 1, payload.dig("stats", "total_outreach_attempted")
    assert_equal 2, payload.dig("stats", "total_outreach_reached")
    assert_equal 2, payload.dig("stats", "total_unmatched_supporters")
    assert_equal @active_import.id, payload.dig("election_day", "active_import_id")
    assert payload["not_yet_voted_queue"].is_a?(Array)
    assert payload["not_yet_voted_queue"].any? { |entry| entry["name"] == "Village A" }
    assert payload["not_yet_voted_supporters"].any? { |entry| entry["id"] == @supporter_a1.id }
    assert_not payload["not_yet_voted_supporters"].any? { |entry| entry["id"] == @supporter_observed.id }
    assert payload["observed_elsewhere_supporters"].any? { |entry| entry["id"] == @supporter_observed.id }
    observed_payload = payload["observed_elsewhere_supporters"].find { |entry| entry["id"] == @supporter_observed.id }
    assert_equal @admin.name, observed_payload["turnout_updated_by_user_name"]
    assert_not payload["not_yet_voted_supporters"].any? { |entry| entry["id"] == @old_supporter.id }
    assert payload["unmatched_supporters"].any? { |entry| entry["id"] == @unmatched_supporter.id }
    assert_not payload["unmatched_supporters"].any? { |entry| entry["id"] == @pending_unmatched_supporter.id }

    village_a = payload["villages"].find { |v| v["name"] == "Village A" }
    assert_equal 2, village_a["not_yet_voted_count"]
    assert_equal 1, village_a["observed_elsewhere_count"]
    assert_equal 1, village_a["outreach_attempted_count"]
    assert_equal 1, village_a["outreach_reached_count"]
  end

  test "not on list incident does not replace latest turnout report for precinct stats" do
    PollReport.create!(
      precinct: @precinct_a,
      voter_count: 0,
      report_type: "not_on_list",
      notes: "Supporter name heard but not on list",
      reported_at: Time.current + 5.minutes
    )

    get "/api/v1/war_room", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)

    village_a = payload["villages"].find { |v| v["name"] == "Village A" }
    assert_equal 100, village_a["voters_reported"]
    assert_equal 28.6, village_a["turnout_pct"]
    assert_equal 2, village_a["not_yet_voted_count"]
    assert_equal 1, village_a["observed_elsewhere_count"]
  end

  test "war room can log contact attempt for supporter in scope" do
    post "/api/v1/war_room/supporters/#{@supporter_a1.id}/contact_attempts",
      params: {
        contact_attempt: {
          outcome: "reached",
          channel: "call",
          note: "Confirmed by war room"
        }
      },
      headers: auth_headers(@admin)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal @supporter_a1.id, payload.dig("contact_attempt", "supporter_id")
    assert_equal "reached", payload.dig("contact_attempt", "outcome")

    attempt = SupporterContactAttempt.find(payload.dig("contact_attempt", "id"))
    audit_log = AuditLog.where(auditable: attempt, action: "created").order(created_at: :desc).first
    assert audit_log.present?
    assert_equal @admin.id, audit_log.actor_user_id
    assert_equal "campaign_operations_not_official_record", audit_log.metadata["compliance_context"]
  end

  test "poll watcher cannot access war room" do
    get "/api/v1/war_room", headers: auth_headers(@watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "war_room_access_required", payload["code"]
  end
end
