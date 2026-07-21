require "test_helper"

class Api::V1::ElectionDayControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(clerk_id: "election-admin", email: "election-admin@example.com", name: "Election Admin", role: "campaign_admin")
    @poll_watcher = User.create!(clerk_id: "election-poll", email: "election-poll@example.com", name: "Election Poll", role: "poll_watcher")
    @village = Village.create!(name: "Hagåtña")
    @precinct = Precinct.create!(village: @village, number: "1")
    @gec_import = GecImport.create!(filename: "gec-may.xlsx", gec_list_date: Date.new(2026, 5, 1), status: "completed", total_records: 2)
    @older_import = GecImport.create!(filename: "gec-april.xlsx", gec_list_date: Date.new(2026, 4, 1), status: "completed", total_records: 1)
    @voter = GecVoter.create!(
      first_name: "Maria", last_name: "Cruz", birth_year: 1980,
      address: "1 Chalan Santo Papa", village: @village, village_name: @village.name,
      precinct: @precinct, precinct_number: @precinct.number,
      voter_registration_number: "GEC-1", gec_list_date: @gec_import.gec_list_date, imported_at: Time.current
    )
    @older_voter = GecVoter.create!(
      first_name: "Old", last_name: "List", birth_year: 1970,
      address: "Old Address", village: @village, village_name: @village.name,
      precinct: @precinct, precinct_number: @precinct.number,
      voter_registration_number: "GEC-OLD", gec_list_date: @older_import.gec_list_date, imported_at: Time.current
    )
    @supporter = Supporter.create!(
      first_name: "Maria", last_name: "Cruz", contact_number: "6715550101",
      village: @village, precinct: @precinct, source: "staff_entry",
      contact_classification: "active_contact", support_status: "supporter",
      status: "active", verification_status: "verified",
      needs_election_day_ride: true
    )
    @supporter.update_columns(gec_voter_id: @voter.id)
    @event = ElectionEvent.create!(name: "2026 Primary Election", election_type: "primary", election_date: Date.new(2026, 8, 1), gec_import: @gec_import)
  end

  test "admin can create and activate election event with selected GEC import" do
    post "/api/v1/election_events",
      params: { election_event: { name: "2026 General Election", election_type: "general", election_date: "2026-11-03", gec_import_id: @gec_import.id } },
      headers: auth_headers(@admin), as: :json

    assert_response :created
    event_id = response.parsed_body.dig("election_event", "id")

    post "/api/v1/election_events/#{event_id}/activate", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal event_id, ElectionEvent.active_event.id
  end

  test "a different current event must be explicitly closed before activation" do
    @event.activate!(actor_user: @admin)
    replacement = ElectionEvent.create!(name: "2026 General Election", election_type: "general", election_date: Date.new(2026, 11, 3), gec_import: @gec_import)

    post "/api/v1/election_events/#{replacement.id}/activate", headers: auth_headers(@admin), as: :json

    assert_response :conflict
    assert_equal "current_election_must_be_closed", response.parsed_body["code"]
    assert_equal "active", @event.reload.status
    assert_equal "setup", replacement.reload.status

    @event.close!(actor_user: @admin)
    post "/api/v1/election_events/#{replacement.id}/activate", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal "active", replacement.reload.status
  end

  test "poll watcher cannot manage election setup" do
    post "/api/v1/election_events",
      params: { election_event: { name: "Blocked", election_type: "primary", election_date: "2026-08-01", gec_import_id: @gec_import.id } },
      headers: auth_headers(@poll_watcher), as: :json

    assert_response :forbidden
  end

  test "update cannot directly activate an election event" do
    patch "/api/v1/election_events/#{@event.id}",
      params: { election_event: { status: "active", name: "Renamed Primary" } },
      headers: auth_headers(@admin), as: :json

    assert_response :success
    @event.reload
    assert_equal "setup", @event.status
    assert_equal "Renamed Primary", @event.name
    assert_nil @event.activated_at
  end

  test "active election event cannot switch GEC imports" do
    @event.activate!(actor_user: @admin)
    replacement_import = GecImport.create!(
      filename: "replacement.csv",
      status: "completed",
      total_records: 1,
      gec_list_date: Date.new(2026, 8, 2)
    )

    patch "/api/v1/election_events/#{@event.id}",
      params: { election_event: { gec_import_id: replacement_import.id } },
      headers: auth_headers(@admin), as: :json

    assert_response :conflict
    assert_equal "active_election_gec_import_locked", response.parsed_body["code"]
    assert_equal @gec_import.id, @event.reload.gec_import_id
  end

  test "command center uses active election GEC list and chase list contact status" do
    @event.activate!(actor_user: @admin)
    SupporterContactAttempt.create!(supporter: @supporter, recorded_by_user: @admin, channel: "call", outcome: "attempted", recorded_at: Time.current)

    get "/api/v1/election_day", headers: auth_headers(@admin), as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal false, payload["setup_required"]
    assert_equal @event.id, payload.dig("active_election", "id")
    assert_equal 1, payload.dig("stats", "total_voters")
    assert_equal 1, payload.dig("stats", "chase_list_count")
    assert_equal 1, payload.dig("stats", "contacted_today")
    refute_includes payload["chase_list"].map { |row| row["gec_voter_id"] }, @older_voter.id
  end

  test "command center reports are scoped to the current election event" do
    @event.activate!(actor_user: @admin)
    other_event = ElectionEvent.create!(name: "Other Election", election_type: "general", election_date: @event.election_date, gec_import: @gec_import)
    PollReport.create!(election_event: @event, precinct: @precinct, user: @poll_watcher, report_type: "turnout_update", voter_count: 10, reported_at: Time.zone.local(2026, 8, 2, 9, 0, 0))
    PollReport.create!(election_event: other_event, precinct: @precinct, user: @poll_watcher, report_type: "turnout_update", voter_count: 99, reported_at: Time.zone.local(2026, 8, 1, 9, 0, 0))

    get "/api/v1/election_day", headers: auth_headers(@admin), as: :json

    assert_response :success
    reports = response.parsed_body["recent_reports"]
    assert_equal 1, reports.size
    assert_equal 10, reports.first["voter_count"]
  end

  test "command center reports full chase totals while bounding the returned page" do
    @event.activate!(actor_user: @admin)
    201.times do |index|
      voter = GecVoter.create!(
        first_name: "Chase", last_name: "Contact#{index}", birth_year: 1980,
        address: "#{index} Chalan Santo Papa", village: @village, village_name: @village.name,
        precinct: @precinct, precinct_number: @precinct.number,
        voter_registration_number: "GEC-CHASE-#{index}", gec_list_date: @gec_import.gec_list_date, imported_at: Time.current
      )
      supporter = Supporter.create!(
        first_name: "Chase", last_name: "Contact#{index}", contact_number: "671555#{format('%04d', index)}",
        village: @village, precinct: @precinct, source: "staff_entry",
        contact_classification: "active_contact", support_status: "supporter",
        status: "active", verification_status: "verified"
      )
      supporter.update_columns(gec_voter_id: voter.id)
    end

    get "/api/v1/election_day", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal 202, response.parsed_body.dig("stats", "chase_list_count")
    assert_equal 50, response.parsed_body["chase_list"].size
    assert_equal 202, response.parsed_body.dig("chase_pagination", "total")
    assert_equal 5, response.parsed_body.dig("chase_pagination", "pages")
  end

  test "poll watcher turnout update creates election scoped record and removes from chase list" do
    @event.activate!(actor_user: @admin)
    PollWatcherPrecinctAssignment.create!(user: @poll_watcher, precinct: @precinct, assigned_at: Time.current)

    patch "/api/v1/poll_watcher/strike_list/#{@voter.id}/turnout",
      params: { turnout: { precinct_id: @precinct.id, turnout_status: "voted", note: "Checked off" } },
      headers: auth_headers(@poll_watcher), as: :json

    assert_response :success
    record = ElectionTurnoutRecord.find_by!(election_event: @event, gec_voter: @voter)
    assert_equal "voted", record.turnout_status
    assert_equal "poll_watcher", record.turnout_source

    get "/api/v1/election_day", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.dig("stats", "voted")
    assert_equal 0, response.parsed_body.dig("stats", "chase_list_count")
  end

  test "command center contact logging rejects contacts outside active election GEC list" do
    @event.activate!(actor_user: @admin)
    outside_supporter = Supporter.create!(
      first_name: "Old", last_name: "List", contact_number: "6715559999",
      village: @village, precinct: @precinct, source: "staff_entry",
      contact_classification: "active_contact", support_status: "supporter",
      status: "active", verification_status: "verified"
    )
    outside_supporter.update_columns(gec_voter_id: @older_voter.id)

    post "/api/v1/election_day/contact",
      params: { supporter_id: outside_supporter.id, contact_attempt: { channel: "call", outcome: "reached", note: "Wrong list" } },
      headers: auth_headers(@admin), as: :json

    assert_response :not_found
    assert_equal "supporter_not_found", response.parsed_body["code"]
    assert_equal 0, outside_supporter.supporter_contact_attempts.count
  end

  test "command center contact logging writes normal contact history and ignores client supplied recorded_at" do
    @event.activate!(actor_user: @admin)
    travel_to Time.zone.local(2026, 8, 1, 10, 30, 0) do
      post "/api/v1/election_day/contact",
        params: { supporter_id: @supporter.id, contact_attempt: { channel: "call", outcome: "reached", note: "Plans to vote after work", recorded_at: 2.days.ago.iso8601 } },
        headers: auth_headers(@admin), as: :json
    end

    assert_response :created
    attempt = @supporter.supporter_contact_attempts.order(:created_at).last
    assert_equal "call", attempt.channel
    assert_equal "reached", attempt.outcome
    assert_includes attempt.note, @event.name
    assert_equal Time.zone.local(2026, 8, 1, 10, 30, 0), attempt.recorded_at
  end

  test "already closed election event cannot be closed again" do
    @event.close!(actor_user: @admin)

    post "/api/v1/election_events/#{@event.id}/close", headers: auth_headers(@admin), as: :json

    assert_response :conflict
    assert_equal "election_event_not_closable", response.parsed_body["code"]
  end

  test "training event is current but cannot be promoted into the live event" do
    post "/api/v1/election_events/#{@event.id}/start_training", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal "training", @event.reload.status
    assert_equal @event.id, ElectionEvent.current_event.id
    assert_equal @admin.id, @event.training_started_by_user_id

    post "/api/v1/election_events/#{@event.id}/activate", headers: auth_headers(@admin), as: :json

    assert_response :conflict
    assert_equal "election_event_not_activatable", response.parsed_body["code"]
  end

  test "a new live election does not inherit turnout from a closed training event" do
    @event.start_training!(actor_user: @admin)
    ElectionTurnoutUpdateService.new(
      election_event: @event,
      gec_voter: @voter,
      actor_user: @admin,
      turnout_status: "voted",
      source: "admin_override"
    ).call
    assert_equal "not_yet_voted", @voter.reload.turnout_status
    @event.close!(actor_user: @admin)
    live_event = ElectionEvent.create!(name: "Clean Live Election", election_type: "primary", election_date: @event.election_date, gec_import: @gec_import)
    live_event.activate!(actor_user: @admin)

    get "/api/v1/election_day", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal live_event.id, response.parsed_body.dig("active_election", "id")
    assert_equal 0, response.parsed_body.dig("stats", "voted")
    assert_equal 1, response.parsed_body.dig("stats", "not_yet_voted")
  end
end
