require "test_helper"

class Api::V1::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = Campaign.create!(
      name: "Reports Campaign",
      election_year: Date.current.year,
      status: "active"
    )
    @district = District.create!(name: "Northern", campaign: @campaign)
    @other_district = District.create!(name: "Central", campaign: @campaign)
    @village = Village.find_or_create_by!(name: "Barrigada")
    @village.update!(district: @district)
    @other_village = Village.find_or_create_by!(name: "Dededo")
    @other_village.update!(district: @other_district)
    Quota.create!(
      campaign: @campaign,
      village: @village,
      target_count: 150,
      period: "monthly"
    )
    @admin = User.create!(
      clerk_id: "clerk-report-admin-#{SecureRandom.hex(4)}",
      email: "report-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Report Admin",
      role: "campaign_admin"
    )
    @data_team = User.create!(
      clerk_id: "clerk-report-data-team-#{SecureRandom.hex(4)}",
      email: "report-data-team-#{SecureRandom.hex(4)}@example.com",
      name: "Report Data Team",
      role: "data_team"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-report-coordinator-#{SecureRandom.hex(4)}",
      email: "report-coordinator-#{SecureRandom.hex(4)}@example.com",
      name: "Report Coordinator",
      role: "district_coordinator",
      assigned_district_id: @district.id
    )

    @cycle = CampaignCycle.create!(
      name: "Reports Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active",
      monthly_quota_target: 4000
    )
    @period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 4000
    )

    Supporter.create!(
      first_name: "Test",
      last_name: "Supporter",
      contact_number: "671-555-9999",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      review_status: "approved",
      public_review_status: "not_applicable",
      quota_period: @period,
      verification_status: "verified",
      verified_at: Time.current,
      registered_voter: true,
      registered_voter_status: "yes",
      needs_voter_registration_help: true,
      registration_outreach_status: "registered"
    )
    Supporter.create!(
      first_name: "Official",
      last_name: "Only",
      contact_number: "671-555-9998",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      review_status: "approved",
      public_review_status: "not_applicable",
      quota_period: @period,
      verification_status: "flagged",
      registered_voter: true,
      registered_voter_status: "not_sure"
    )
    Supporter.create!(
      first_name: "Referral",
      last_name: "Supporter",
      contact_number: "671-555-9997",
      village: @other_village,
      submitted_village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "flagged",
      registered_voter: true,
      registered_voter_status: "no",
      needs_absentee_ballot_help: true,
      registration_outreach_status: "contacted"
    )
    GecVoter.create!(
      first_name: "Moved",
      last_name: "Voter",
      village_name: @village.name,
      previous_village_name: "Dededo",
      voter_registration_number: "VRN-MOVED",
      status: "active",
      gec_list_date: Date.current,
      imported_at: Time.current
    )
    GecVoter.create!(
      first_name: "Unassigned",
      last_name: "Voter",
      village_name: GecImportService::UNASSIGNED_VILLAGE_NAME,
      previous_village_name: "Yigo",
      voter_registration_number: "VRN-UNASSIGNED",
      status: "active",
      gec_list_date: Date.current,
      imported_at: Time.current
    )
  end

  test "index returns available reports" do
    get "/api/v1/reports", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 6, json["available_reports"].size
    assert_equal 3, json["quick_stats"]["official_supporters"]
    assert_equal 1, json["quick_stats"]["matched_to_gec"]
    assert_equal 1, json["quick_stats"]["quota_eligible"]
    assert_equal 2, json["quick_stats"]["current_quota_progress"]
    assert_equal 1, json["quick_stats"]["transfer_list_size"]
    assert_equal 1, json["quick_stats"]["referral_list_size"]
    assert_equal 1, json["quick_stats"]["mapping_issues_list_size"]
    assert json["quick_stats"].key?("purge_list_size")
    assert json["quick_stats"].key?("latest_import_removed_voters")
  end

  test "show generates support list xlsx" do
    get "/api/v1/reports/support_list", headers: auth_headers(@admin)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.content_type
    assert_match(/support-list/, response.headers["Content-Disposition"])
  end

  test "preview returns support list rows" do
    get "/api/v1/reports/support_list/preview", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "support_list", json["report_type"]
    assert json["columns"].length > 0
    assert json["rows"].length > 0
    assert_equal 3, json["total_count"]
  end

  test "preview returns Becky-filtered support list rows" do
    get "/api/v1/reports/support_list/preview",
      params: {
        registered_voter_status: "yes",
        support_need: "registration",
        registration_outreach_status: "registered"
      },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total_count"]
    assert_equal "Test", json["rows"].first[1]
    assert_includes json["columns"], "Registration Follow-Up Result"
    assert_equal "registered", json.dig("filters", "registration_outreach_status")
  end

  test "data team can access reports" do
    get "/api/v1/reports", headers: auth_headers(@data_team)

    assert_response :success
  end

  test "district coordinator can access limited reports only" do
    get "/api/v1/reports", headers: auth_headers(@coordinator)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal %w[quota_summary referral_list support_list], json["available_reports"].map { |report| report["type"] }.sort
  end

  test "district coordinator is denied full data ops report types" do
    get "/api/v1/reports/purge_list", headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "report_type_access_denied", payload["code"]
  end

  test "district coordinator reports are automatically scoped to assigned district" do
    get "/api/v1/reports/support_list/preview", headers: auth_headers(@coordinator)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @district.id, json.dig("filters", "district_id")
    assert_equal 2, json["total_count"]
  end

  test "show generates quota summary xlsx" do
    get "/api/v1/reports/quota_summary", headers: auth_headers(@admin)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.content_type
  end

  test "show filters by village" do
    get "/api/v1/reports/support_list", params: { village_id: @village.id }, headers: auth_headers(@admin)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.content_type
  end

  test "quota summary preview falls back to legacy village targets when period rows are missing" do
    get "/api/v1/reports/quota_summary/preview", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    barrigada = json["rows"].find { |row| row[0] == "Barrigada" }
    assert barrigada.present?
    assert_equal 150, barrigada[1]
    assert_equal 2, barrigada[2]
  end

  test "show rejects invalid report type" do
    get "/api/v1/reports/nonexistent", headers: auth_headers(@admin)

    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    get "/api/v1/reports"

    assert_response :unauthorized
  end

  test "district coordinator cannot request a village outside assigned district" do
    get "/api/v1/reports/support_list/preview",
      params: { village_id: @other_village.id },
      headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "village_scope_denied", payload["code"]
  end
end
