require "test_helper"

class Api::V1::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      clerk_id: "clerk-dashboard-user",
      email: "dashboard-user@example.com",
      name: "Dashboard User",
      role: "campaign_admin"
    )

    @campaign = Campaign.create!(
      name: "Dashboard Campaign",
      election_year: Date.current.year,
      status: "active"
    )

    @village = Village.create!(name: "Dashboard Village", region: "Central")
    Precinct.create!(number: "D1", village: @village)

    Supporter.create!(
      first_name: "Supporter", last_name: "One", print_name: "Supporter One",
      contact_number: "6715551000",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "verified",
      # Created before this week, but vetted now.
      created_at: 10.days.ago,
      verified_at: Time.current
    )
    Supporter.create!(
      first_name: "Supporter", last_name: "Two", print_name: "Supporter Two",
      contact_number: "6715551001",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "verified"
    )
    Supporter.create!(
      first_name: "Supporter", last_name: "Three", print_name: "Supporter Three",
      contact_number: "6715551002",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified"
    )
    Supporter.create!(
      first_name: "Supporter", last_name: "Four", print_name: "Supporter Four",
      contact_number: "6715551004",
      village: @village,
      source: "qr_signup",
      intake_status: "accepted",
      public_review_status: "approved",
      review_status: "approved",
      status: "active",
      verification_status: "verified"
    )
    Supporter.create!(
      first_name: "Supporter", last_name: "Five", print_name: "Supporter Five",
      contact_number: "6715551005",
      village: @village,
      source: "public_signup",
      intake_status: "pending_public_review",
      public_review_status: "pending",
      review_status: "pending",
      status: "active",
      verification_status: "unverified"
    )
    Supporter.create!(
      first_name: "Supporter", last_name: "Six", print_name: "Supporter Six",
      contact_number: "6715551006",
      village: @village,
      source: "bulk_import",
      intake_status: "accepted",
      public_review_status: "not_applicable",
      review_status: "pending",
      status: "active",
      verification_status: "unverified"
    )
  end

  test "show returns aggregated dashboard payload with vetting separation" do
    get "/api/v1/dashboard", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal "Dashboard Campaign", payload.dig("campaign", "name")

    # Verified supporters are the primary count
    assert_equal 3, payload.dig("summary", "verified_supporters")
    # Total includes unverified
    assert_equal 4, payload.dig("summary", "total_supporters")
    assert_equal 1, payload.dig("summary", "unverified_supporters")
    # Today/week counts are verified only
    assert_equal 3, payload.dig("summary", "today_signups")
    assert_equal 3, payload.dig("summary", "week_signups")

    assert_equal 1, payload["villages"].size
    village = payload["villages"][0]
    # Village counts reflect vetting separation
    assert_equal 3, village["verified_count"]
    assert_equal 4, village["total_count"]
    assert_equal 1, village["unverified_count"]
    # supporter_count = verified (backward compat)
    assert_equal 3, village["supporter_count"]
    assert_equal 3, village["team_input_count"]
    assert_equal 1, village["public_approved_count"]
    assert_equal 1, village["team_pending_count"]
    assert_equal 1, village["public_signup_count"]
  end

  test "show excludes unassigned village from total village summary" do
    Village.create!(name: "Unassigned", region: "Other")

    get "/api/v1/dashboard", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload.dig("summary", "total_villages")
    assert_equal 2, payload["villages"].size
  end

  test "scoped user sees island-wide summary with scoped village list" do
    other_village = Village.create!(name: "Other Village", region: "North")
    Precinct.create!(number: "O1", village: other_village)
    Supporter.create!(
      first_name: "Supporter", last_name: "Four", print_name: "Supporter Four",
      contact_number: "6715551003",
      village: other_village,
      source: "staff_entry",
      status: "active",
      verification_status: "verified",
      verified_at: Time.current
    )

    scoped_user = User.create!(
      clerk_id: "clerk-dashboard-scoped-user",
      email: "dashboard-scoped-user@example.com",
      name: "Dashboard Scoped User",
      role: "block_leader",
      assigned_village_id: @village.id
    )

    get "/api/v1/dashboard", headers: auth_headers(scoped_user)

    assert_response :success
    payload = JSON.parse(response.body)

    # Summary remains island-wide.
    assert_equal 5, payload.dig("summary", "total_supporters")
    assert_equal 4, payload.dig("summary", "verified_supporters")

    # Village cards are scoped to the assigned village.
    assert_equal 1, payload["villages"].size
    assert_equal @village.id, payload["villages"][0]["id"]
  end
end
