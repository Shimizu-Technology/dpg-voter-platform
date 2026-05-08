require "test_helper"

class Api::V1::PrecinctsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @village = Village.create!(
      name: "Tamuning",
      region: "Central"
    )
    @precinct = Precinct.create!(
      village: @village,
      number: "15A",
      alpha_range: "A-K",
      polling_site: "Tamuning Elementary",
      registered_voters: 600,
      active: true
    )
    @admin = User.create!(
      clerk_id: "clerk-admin-precinct",
      email: "admin-precinct@example.com",
      name: "Admin",
      role: "campaign_admin"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator-precinct",
      email: "coordinator-precinct@example.com",
      name: "Coordinator",
      role: "district_coordinator"
    )
    @leader = User.create!(
      clerk_id: "clerk-leader-precinct",
      email: "leader-precinct@example.com",
      name: "Leader",
      role: "block_leader"
    )
  end

  test "non coordinator cannot list precincts" do
    get "/api/v1/precincts", headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "coordinator_access_required", payload["code"]
  end

  test "coordinator can list precincts" do
    Supporter.create!(
      first_name: "Active", last_name: "Linked", print_name: "Active Linked",
      contact_number: "671-555-0110",
      village: @village,
      precinct: @precinct,
      status: "active",
      source: "staff_entry",
      registered_voter: true,
      yard_sign: false,
      motorcade_available: false
    )
    Supporter.create!(
      first_name: "Removed", last_name: "Linked", print_name: "Removed Linked",
      contact_number: "671-555-0111",
      village: @village,
      precinct: @precinct,
      status: "removed",
      source: "staff_entry",
      registered_voter: true,
      yard_sign: false,
      motorcade_available: false
    )

    get "/api/v1/precincts", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    row = payload["precincts"].find { |p| p["id"] == @precinct.id }
    assert_not_nil row
    assert_equal "Tamuning", row["village_name"]
    assert_equal 1, row["linked_supporters_count"]
  end

  test "admin can update precinct metadata and audit is written" do
    patch "/api/v1/precincts/#{@precinct.id}",
      params: { precinct: { polling_site: "New Site", alpha_range: "A-M", registered_voters: 650, change_note: "Polling location update" } },
      headers: auth_headers(@admin)

    assert_response :success
    @precinct.reload
    assert_equal "New Site", @precinct.polling_site
    assert_equal "A-M", @precinct.alpha_range
    assert_equal 650, @precinct.registered_voters
    audit = AuditLog.where(auditable: @precinct).order(created_at: :desc).first
    assert_not_nil audit
    assert_equal "updated", audit.action
    assert_equal "Tamuning Elementary", audit.changed_data.dig("polling_site", "from")
    assert_equal "New Site", audit.changed_data.dig("polling_site", "to")
    assert_equal 600, audit.changed_data.dig("registered_voters", "from")
    assert_equal 650, audit.changed_data.dig("registered_voters", "to")
    assert_equal "Polling location update", audit.metadata["change_note"]
  end

  test "cannot deactivate precinct with assigned supporters" do
    Supporter.create!(
      first_name: "Assigned", last_name: "Person", print_name: "Assigned Person",
      contact_number: "671-555-0101",
      village: @village,
      precinct: @precinct,
      status: "active",
      source: "staff_entry",
      registered_voter: true,
      yard_sign: false,
      motorcade_available: false
    )

    patch "/api/v1/precincts/#{@precinct.id}",
      params: { precinct: { active: false } },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "precinct_in_use", payload["code"]
    assert @precinct.reload.active
  end

  test "can deactivate precinct when only non-active supporters are assigned" do
    Supporter.create!(
      first_name: "Removed", last_name: "Person", print_name: "Removed Person",
      contact_number: "671-555-0102",
      village: @village,
      precinct: @precinct,
      status: "removed",
      source: "staff_entry",
      registered_voter: true,
      yard_sign: false,
      motorcade_available: false
    )

    patch "/api/v1/precincts/#{@precinct.id}",
      params: { precinct: { active: false } },
      headers: auth_headers(@admin)

    assert_response :success
    assert_equal false, @precinct.reload.active
  end

  test "invalid registered voters is rejected for precinct update" do
    patch "/api/v1/precincts/#{@precinct.id}",
      params: { precinct: { registered_voters: 0 } },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "invalid_registered_voters", payload["code"]
  end
end
