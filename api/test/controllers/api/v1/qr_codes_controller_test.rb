require "test_helper"

class Api::V1::QrCodesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @campaign = Campaign.create!(
      name: "QR Campaign",
      election_year: Date.current.year,
      status: "active"
    )
    @district = District.create!(name: "Central", campaign: @campaign)
    @village_a = Village.create!(name: "QR Village A", district: @district)
    @village_b = Village.create!(name: "QR Village B")

    @coordinator = User.create!(
      clerk_id: "clerk-qr-coordinator",
      email: "qr-coordinator@example.com",
      name: "QR Coordinator",
      role: "district_coordinator",
      assigned_district_id: @district.id
    )
    @admin = User.create!(
      clerk_id: "clerk-qr-admin",
      email: "qr-admin@example.com",
      name: "QR Admin",
      role: "campaign_admin"
    )
    @leader_a = User.create!(
      clerk_id: "clerk-qr-leader-a",
      email: "leader-a@example.com",
      name: "Leader A",
      role: "block_leader",
      assigned_village_id: @village_a.id
    )
    @leader_b = User.create!(
      clerk_id: "clerk-qr-leader-b",
      email: "leader-b@example.com",
      name: "Leader B",
      role: "block_leader",
      assigned_village_id: @village_b.id
    )
  end

  test "generate persists referral code for assigned user" do
    post "/api/v1/qr_codes/generate",
      params: {
        assigned_user_id: @leader_a.id,
        village_id: @village_a.id
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["code"].present?
    assert_equal @leader_a.id, payload.dig("referral_code", "assigned_user_id")
    assert_equal @village_a.id, payload.dig("referral_code", "village_id")
    assert_equal "Leader A", payload.dig("referral_code", "display_name")

    record = ReferralCode.find_by(code: payload["code"])
    assert_not_nil record
    assert_equal @coordinator.id, record.created_by_user_id
  end

  test "generate rejects assigned user outside selected village scope" do
    post "/api/v1/qr_codes/generate",
      params: {
        assigned_user_id: @leader_a.id,
        village_id: @village_b.id
      },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "assigned_user_village_mismatch", payload["code"]
  end

  test "assignees endpoint only returns users in accessible scope" do
    get "/api/v1/qr_codes/assignees", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    ids = payload.fetch("users").map { |row| row.fetch("id") }
    assert_includes ids, @leader_a.id
    assert_not_includes ids, @leader_b.id
  end
end
