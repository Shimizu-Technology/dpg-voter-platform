require "test_helper"

class Api::V1::SessionControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      clerk_id: "clerk-session-admin",
      email: "session-admin@example.com",
      name: "Session Admin",
      role: "campaign_admin"
    )
    @data_team = User.create!(
      clerk_id: "clerk-session-data-team",
      email: "session-data-team@example.com",
      name: "Session Data Team",
      role: "data_team"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-session-coordinator",
      email: "session-coordinator@example.com",
      name: "Session Coordinator",
      role: "district_coordinator"
    )
    @poll_watcher = User.create!(
      clerk_id: "clerk-session-pw",
      email: "session-pw@example.com",
      name: "Session Poll Watcher",
      role: "poll_watcher"
    )
  end

  test "admin session permissions include management tools" do
    get "/api/v1/session", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload.dig("permissions", "can_manage_users")
    assert_equal true, payload.dig("permissions", "can_send_sms")
    assert_equal true, payload.dig("permissions", "can_access_events")
    assert_equal true, payload.dig("permissions", "can_access_audit_logs")
    assert_equal "/admin", payload.dig("permissions", "default_route")
  end

  test "data team session permissions stay focused on data ops" do
    get "/api/v1/session", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal false, payload.dig("permissions", "can_manage_users")
    assert_equal false, payload.dig("permissions", "can_manage_configuration")
    assert_equal true, payload.dig("permissions", "can_manage_data_configuration")
    assert_equal false, payload.dig("permissions", "can_send_sms")
    assert_equal false, payload.dig("permissions", "can_send_email")
    assert_equal false, payload.dig("permissions", "can_access_events")
    assert_equal false, payload.dig("permissions", "can_access_qr")
    assert_equal false, payload.dig("permissions", "can_access_war_room")
    assert_equal true, payload.dig("permissions", "can_import_supporters")
    assert_equal true, payload.dig("permissions", "can_access_data_team")
    assert_equal true, payload.dig("permissions", "can_access_reports")
    assert_equal true, payload.dig("permissions", "can_upload_gec")
    assert_equal true, payload.dig("permissions", "can_bulk_vet")
    assert_equal true, payload.dig("permissions", "can_review_public")
    assert_equal "/data", payload.dig("permissions", "default_route")
  end

  test "district coordinator session permissions stay field-ops focused" do
    get "/api/v1/session", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload.dig("permissions", "can_manage_users")
    assert_equal false, payload.dig("permissions", "can_manage_configuration")
    assert_equal false, payload.dig("permissions", "can_manage_data_configuration")
    assert_equal true, payload.dig("permissions", "can_send_sms")
    assert_equal true, payload.dig("permissions", "can_send_email")
    assert_equal true, payload.dig("permissions", "can_access_events")
    assert_equal true, payload.dig("permissions", "can_access_war_room")
    assert_equal true, payload.dig("permissions", "can_access_poll_watcher")
    assert_equal true, payload.dig("permissions", "can_import_supporters")
    assert_equal false, payload.dig("permissions", "can_access_data_team")
    assert_equal true, payload.dig("permissions", "can_access_reports")
    assert_equal false, payload.dig("permissions", "can_upload_gec")
    assert_equal false, payload.dig("permissions", "can_review_public")
    assert_equal "/admin", payload.dig("permissions", "default_route")
  end

  test "poll watcher session permissions are restricted to election-day tools" do
    get "/api/v1/session", headers: auth_headers(@poll_watcher)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal false, payload.dig("permissions", "can_manage_users")
    assert_equal false, payload.dig("permissions", "can_view_supporters")
    assert_equal false, payload.dig("permissions", "can_import_supporters")
    assert_equal false, payload.dig("permissions", "can_manage_data_configuration")
    assert_equal true, payload.dig("permissions", "can_access_poll_watcher")
    assert_equal false, payload.dig("permissions", "can_access_war_room")
    assert_equal false, payload.dig("permissions", "can_access_audit_logs")
  end

  test "session exposes official supporter and current period counts" do
    village = Village.create!(name: "Session Village")
    campaign = Campaign.create!(
      name: "Session Campaign",
      election_year: Date.current.year,
      status: "active"
    )
    Quota.create!(
      campaign: campaign,
      village: village,
      target_count: 325,
      period: "monthly"
    )
    cycle = CampaignCycle.create!(
      name: "Session Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    period = QuotaPeriod.create!(
      campaign_cycle: cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 250
    )
    Supporter.create!(
      first_name: "Session",
      last_name: "Supporter",
      contact_number: "6715550101",
      village: village,
      source: "staff_entry",
      status: "active",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "verified",
      quota_period: period
    )
    Supporter.create!(
      first_name: "Session",
      last_name: "Unverified",
      contact_number: "6715550102",
      village: village,
      source: "staff_entry",
      status: "active",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "unverified",
      quota_period: period
    )

    get "/api/v1/session", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 2, payload.dig("counts", "official_supporters")
    assert_equal 1, payload.dig("counts", "matched_to_gec")
    assert_equal 1, payload.dig("counts", "quota_eligible")
    assert_equal 325, payload.dig("current_period", "quota_target")
    assert_equal 2, payload.dig("current_period", "official_count")
    assert_equal 1, payload.dig("current_period", "matched_count")
  end
end
