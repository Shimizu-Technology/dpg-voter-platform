require "test_helper"

class Api::V1::LeaderboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @campaign = Campaign.create!(
      name: "Leaderboard Campaign",
      election_year: Date.current.year,
      status: "active"
    )
    @district = District.create!(name: "Leaderboard District", campaign: @campaign)
    @village = Village.create!(name: "Leaderboard Village", district: @district)

    @admin = User.create!(
      clerk_id: "clerk-lb-admin",
      email: "lb-admin@example.com",
      name: "LB Admin",
      role: "campaign_admin"
    )
    @leader = User.create!(
      clerk_id: "clerk-lb-leader",
      email: "lb-leader@example.com",
      name: "LB Leader",
      role: "block_leader",
      assigned_village_id: @village.id
    )
    @staff = User.create!(
      clerk_id: "clerk-lb-staff",
      email: "lb-staff@example.com",
      name: "LB Staff",
      role: "district_coordinator",
      assigned_district_id: @district.id
    )

    @referral_code = ReferralCode.create!(
      code: "LB-VIL-0001",
      display_name: "LB Leader",
      village: @village,
      assigned_user: @leader,
      created_by_user: @admin
    )
  end

  test "leaderboard returns QR plus manual/scan/import breakdown" do
    create_supporter!(
      first_name: "Qr",
      last_name: "One",
      contact_number: "6715551200",
      village: @village,
      status: "active",
      source: "qr_signup",
      attribution_method: "qr_self_signup",
      leader_code: @referral_code.code,
      referral_code: @referral_code
    )
    create_supporter!(
      first_name: "Manual",
      last_name: "Entry",
      contact_number: "6715551201",
      village: @village,
      status: "active",
      source: "staff_entry",
      attribution_method: "staff_manual",
      entered_by: @staff
    )
    create_supporter!(
      first_name: "Scan",
      last_name: "Entry",
      contact_number: "6715551202",
      village: @village,
      status: "active",
      source: "staff_entry",
      attribution_method: "staff_scan",
      entered_by: @staff
    )
    create_supporter!(
      first_name: "Import",
      last_name: "Entry",
      contact_number: "6715551203",
      village: @village,
      status: "active",
      source: "bulk_import",
      attribution_method: "bulk_import",
      entered_by: @staff
    )

    get "/api/v1/leaderboard", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)

    leader_row = payload.fetch("leaderboard").find { |row| row["owner_name"] == "LB Leader" }
    staff_row = payload.fetch("leaderboard").find { |row| row["owner_name"] == "LB Staff" }

    assert_not_nil leader_row
    assert_not_nil staff_row
    assert_equal 1, leader_row["qr_signups"]
    assert_equal 1, staff_row["manual_entries"]
    assert_equal 1, staff_row["scan_entries"]
    assert_equal 1, staff_row["import_entries"]
    assert_equal 3, staff_row["total_added"]

    assert_equal 1, payload.dig("stats", "total_qr_signups")
    assert_equal 1, payload.dig("stats", "total_manual_entries")
    assert_equal 1, payload.dig("stats", "total_scan_entries")
    assert_equal 1, payload.dig("stats", "total_import_entries")
    assert_equal 4, payload.dig("stats", "total_added")
  end

  private

  def create_supporter!(attrs)
    Supporter.create!(
      {
        first_name: "First",
        last_name: "Last",
        contact_number: "6715559999",
        village: @village,
        status: "active",
        source: "staff_entry",
        attribution_method: "staff_manual",
        verification_status: "unverified",
        turnout_status: "unknown"
      }.merge(attrs)
    )
  end
end
