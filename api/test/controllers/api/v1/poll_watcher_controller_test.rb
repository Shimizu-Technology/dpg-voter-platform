require "test_helper"

class Api::V1::PollWatcherControllerTest < ActionDispatch::IntegrationTest
  def setup
    campaign = Campaign.create!(name: "Poll Watcher Campaign", election_year: Date.current.year, status: "active")
    district_one = District.create!(campaign: campaign, name: "District 1", number: 1)
    district_two = District.create!(campaign: campaign, name: "District 2", number: 2)

    @village_one = Village.create!(name: "Village One")
    @village_two = Village.create!(name: "Village Two")
    @village_one.update!(district: district_one)
    @village_two.update!(district: district_two)

    @precinct_one = Precinct.create!(number: "1", village: @village_one, registered_voters: 100)
    @precinct_three = Precinct.create!(number: "3", village: @village_one, registered_voters: 100)
    @precinct_two = Precinct.create!(number: "2", village: @village_two, registered_voters: 100)
    @active_import = GecImport.create!(
      gec_list_date: Date.current,
      filename: "active.csv",
      status: "completed",
      import_type: "full_list",
      active_election_day: true
    )

    @watcher = User.create!(
      clerk_id: "clerk-watcher",
      email: "watcher@example.com",
      name: "Watcher",
      role: "poll_watcher",
      assigned_village_id: @village_one.id
    )
    PollWatcherPrecinctAssignment.create!(user: @watcher, precinct: @precinct_one, assigned_by_user: @watcher)
    @chief = User.create!(
      clerk_id: "clerk-chief",
      email: "chief@example.com",
      name: "Village Chief",
      role: "village_chief",
      assigned_village_id: @village_one.id
    )
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator",
      email: "coordinator@example.com",
      name: "District Coordinator",
      role: "district_coordinator",
      assigned_district_id: district_one.id
    )
    @data_team = User.create!(
      clerk_id: "clerk-data-team",
      email: "data-team@example.com",
      name: "Data Team",
      role: "data_team"
    )
    @block_leader = User.create!(
      clerk_id: "clerk-block-leader",
      email: "leader@example.com",
      name: "Block Leader",
      role: "block_leader",
      assigned_village_id: @village_one.id
    )

    @supporter_assigned = Supporter.create!(
      first_name: "Assigned", last_name: "Supporter", print_name: "Assigned Supporter",
      contact_number: "6715551111",
      village: @village_one,
      precinct: @precinct_one,
      source: "staff_entry",
      status: "active"
    )
    @assigned_voter = GecVoter.create!(
      first_name: "Assigned",
      last_name: "Supporter",
      village: @village_one,
      village_name: @village_one.name,
      precinct: @precinct_one,
      precinct_number: @precinct_one.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @supporter_assigned.update!(gec_voter: @assigned_voter)

    @supporter_unassigned = Supporter.create!(
      first_name: "Unassigned", last_name: "Supporter", print_name: "Unassigned Supporter",
      contact_number: "6715552222",
      village: @village_two,
      precinct: @precinct_two,
      source: "staff_entry",
      status: "active"
    )
    @unassigned_voter = GecVoter.create!(
      first_name: "Unassigned",
      last_name: "Supporter",
      village: @village_two,
      village_name: @village_two.name,
      precinct: @precinct_two,
      precinct_number: @precinct_two.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @supporter_unassigned.update!(gec_voter: @unassigned_voter)
    @same_village_unassigned_voter = GecVoter.create!(
      first_name: "Same",
      last_name: "Village",
      village: @village_one,
      village_name: @village_one.name,
      precinct: @precinct_three,
      precinct_number: @precinct_three.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @future_voter = GecVoter.create!(
      first_name: "Future",
      last_name: "List",
      village: @village_one,
      village_name: @village_one.name,
      precinct: @precinct_one,
      precinct_number: @precinct_one.number,
      gec_list_date: Date.current + 1.day,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @stale_precinct_supporter = Supporter.create!(
      first_name: "Stale", last_name: "Precinct", print_name: "Stale Precinct",
      contact_number: "6715553333",
      village: @village_one,
      precinct: @precinct_three,
      source: "staff_entry",
      status: "active"
    )
    @stale_precinct_voter = GecVoter.create!(
      first_name: "Stale",
      last_name: "Precinct",
      village: @village_one,
      village_name: @village_one.name,
      precinct: @precinct_one,
      precinct_number: @precinct_one.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
    @stale_precinct_supporter.update!(gec_voter: @stale_precinct_voter)
  end

  test "poll watcher index only returns assigned village precincts" do
    get "/api/v1/poll_watcher", headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    villages = payload["villages"]
    assert_equal 1, villages.length
    assert_equal @village_one.id, villages.first["id"]
    assert_equal [ @precinct_one.id ], villages.first["precincts"].map { |row| row["id"] }
  end

  test "poll watcher cannot submit report for unassigned precinct" do
    post "/api/v1/poll_watcher/report",
      params: {
        report: {
          precinct_id: @precinct_two.id,
          voter_count: 20,
          report_type: "turnout_update"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "precinct_not_authorized", payload["code"]
  end

  test "poll watcher can submit report for assigned precinct" do
    post "/api/v1/poll_watcher/report",
      params: {
        report: {
          precinct_id: @precinct_one.id,
          voter_count: 25,
          report_type: "turnout_update"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal @precinct_one.number, payload.dig("report", "precinct_number")
  end

  test "poll watcher can submit name not on list incident for assigned precinct" do
    post "/api/v1/poll_watcher/report",
      params: {
        report: {
          precinct_id: @precinct_one.id,
          voter_count: 0,
          report_type: "not_on_list",
          notes: "Stassie Shimizu reported at site but no election-day voter row was found"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "not_on_list", payload.dig("report", "report_type")
    report = PollReport.find(payload.dig("report", "id"))
    assert_equal "Stassie Shimizu reported at site but no election-day voter row was found", report.notes
    assert_equal 0, report.voter_count
  end

  test "block leader cannot access poll watcher strike list endpoint" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id },
      headers: auth_headers(@block_leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "poll_watcher_access_required", payload["code"]
  end

  test "village chief cannot view strike list endpoint" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id },
      headers: auth_headers(@chief)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "poll_watcher_access_required", payload["code"]
  end

  test "district coordinator cannot view strike list outside assigned district" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_two.id },
      headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "precinct_not_authorized", payload["code"]
  end

  test "data team cannot access poll watcher strike list endpoint" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id },
      headers: auth_headers(@data_team)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "poll_watcher_access_required", payload["code"]
  end

  test "poll watcher can view strike list for assigned precinct" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_match(/Campaign operations tracking only/i, payload["compliance_note"])
    assert_equal @precinct_one.id, payload.dig("precinct", "id")
    assert_equal 2, payload["voters"].length
    voter_ids = payload["voters"].map { |row| row["id"] }
    assert_includes voter_ids, @assigned_voter.id
    assigned_row = payload["voters"].find { |row| row["id"] == @assigned_voter.id }
    assert_equal 1, assigned_row.dig("supporter_overlay", "supporter_count")
    refute assigned_row.dig("supporter_overlay", "primary_supporter")
    assert_equal @active_import.id, payload.dig("election_day", "active_import_id")
  end

  test "poll watcher strike list search matches multi-token full names" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id, search: "assigned supporter" },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ @assigned_voter.id ], payload["voters"].map { |row| row["id"] }
  end

  test "poll watcher strike list search matches last comma first format" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id, search: "supporter, assigned" },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ @assigned_voter.id ], payload["voters"].map { |row| row["id"] }
  end

  test "poll watcher strike list exposes out-of-precinct search matches separately" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id, search: "unassigned supporter" },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_empty payload["voters"]
    assert_equal [ @unassigned_voter.id ], payload["external_matches"].map { |row| row["id"] }
    external_row = payload["external_matches"].first
    assert_equal true, external_row["out_of_precinct"]
    assert_equal @precinct_two.number, external_row["precinct_number"]
    assert_equal @village_two.name, external_row["village_name"]
  end

  test "active election-day list excludes voters from other list dates" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_one.id, turnout_status: "not_yet_voted" },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    voter_ids = payload["voters"].map { |row| row["id"] }
    assert_includes voter_ids, @assigned_voter.id
    assert_not_includes voter_ids, @future_voter.id
  end

  test "poll watcher assignment narrows access within assigned village" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_three.id },
      headers: auth_headers(@watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "precinct_not_authorized", payload["code"]
  end

  test "poll watcher cannot view strike list for unassigned precinct" do
    get "/api/v1/poll_watcher/strike_list",
      params: { precinct_id: @precinct_two.id },
      headers: auth_headers(@watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "precinct_not_authorized", payload["code"]
  end

  test "poll watcher can update turnout for assigned voter" do
    patch "/api/v1/poll_watcher/strike_list/#{@assigned_voter.id}/turnout",
      params: {
        turnout: {
          precinct_id: @precinct_one.id,
          turnout_status: "voted",
          note: "Confirmed at polling site"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_match(/Campaign operations tracking only/i, payload["compliance_note"])
    assert_equal "voted", payload.dig("voter", "turnout_status")
    assert_equal "poll_watcher", payload.dig("voter", "turnout_source")

    audit_log = AuditLog.where(auditable: @assigned_voter, action: "turnout_updated").order(created_at: :desc).first
    assert audit_log.present?
    assert_equal @watcher.id, audit_log.actor_user_id
    assert_equal "campaign_operations_not_official_record", audit_log.metadata["compliance_context"]
    assert_equal "not_yet_voted", audit_log.changed_data.dig("turnout_status", "from")
    assert_equal "voted", audit_log.changed_data.dig("turnout_status", "to")
    assert_equal "voted", @supporter_assigned.reload.turnout_status
  end

  test "poll watcher can mark out-of-precinct voter as observed elsewhere" do
    patch "/api/v1/poll_watcher/strike_list/#{@unassigned_voter.id}/turnout",
      params: {
        turnout: {
          precinct_id: @precinct_one.id,
          turnout_status: "observed_elsewhere",
          note: "Said they voted here instead"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "observed_elsewhere", payload.dig("voter", "turnout_status")
    assert_equal true, payload.dig("voter", "out_of_precinct")
    assert_match(/Observed at Precinct 1 \(Village One\)\./, payload.dig("voter", "turnout_note"))
    assert_match(/Said they voted here instead/, payload.dig("voter", "turnout_note"))

    audit_log = AuditLog.where(auditable: @unassigned_voter, action: "turnout_updated").order(created_at: :desc).first
    assert audit_log.present?
    assert_equal @precinct_one.id, audit_log.metadata["observation_precinct_id"]
    assert_equal @precinct_one.number, audit_log.metadata["observation_precinct_number"]
    assert_equal @village_one.name, audit_log.metadata["observation_village_name"]

    @unassigned_voter.reload
    @supporter_unassigned.reload
    assert_equal "observed_elsewhere", @unassigned_voter.turnout_status
    assert_equal "observed_elsewhere", @supporter_unassigned.turnout_status
    assert_equal @precinct_two.id, @supporter_unassigned.precinct_id
  end

  test "poll watcher cannot clear observed elsewhere exception for out-of-precinct voter" do
    @unassigned_voter.update!(
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct 1 (Village One)."
    )
    @supporter_unassigned.update!(
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct 1 (Village One)."
    )

    patch "/api/v1/poll_watcher/strike_list/#{@unassigned_voter.id}/turnout",
      params: {
        turnout: {
          precinct_id: @precinct_one.id,
          turnout_status: "unknown",
          note: ""
        }
      },
      headers: auth_headers(@watcher)

    assert_response :not_found
    payload = JSON.parse(response.body)
    assert_equal "voter_not_found", payload["code"]
    assert_equal "observed_elsewhere", @unassigned_voter.reload.turnout_status
    assert_equal "observed_elsewhere", @supporter_unassigned.reload.turnout_status
  end

  test "coordinator can clear observed elsewhere exception for out-of-precinct voter within district" do
    @same_village_unassigned_voter.update!(
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct 1 (Village One)."
    )

    patch "/api/v1/poll_watcher/strike_list/#{@same_village_unassigned_voter.id}/turnout",
      params: {
        turnout: {
          precinct_id: @precinct_one.id,
          turnout_status: "unknown",
          note: ""
        }
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "unknown", payload.dig("voter", "turnout_status")
    assert_equal true, payload.dig("voter", "out_of_precinct")
    assert_equal "unknown", @same_village_unassigned_voter.reload.turnout_status
  end

  test "poll watcher cannot update turnout for voter outside assigned precinct" do
    patch "/api/v1/poll_watcher/strike_list/#{@unassigned_voter.id}/turnout",
      params: {
        turnout: {
          precinct_id: @precinct_two.id,
          turnout_status: "voted"
        }
      },
      headers: auth_headers(@watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "precinct_not_authorized", payload["code"]
  end
end
