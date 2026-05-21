# frozen_string_literal: true

require "test_helper"

class Api::V1::ReferralCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @admin = User.create!(
      clerk_id: "clerk-referral-admin-#{SecureRandom.hex(4)}",
      email: "referral-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Referral Admin",
      role: "campaign_admin"
    )
  end

  test "index defaults to active links and supports inactive filter search and pagination" do
    active_code = ReferralCode.create!(
      code: "ACTIVE-BAR-1234",
      display_name: "Active Tamuning canvass",
      village: @village,
      created_by_user: @admin,
      active: true,
      metadata: { "source_type" => "village", "notes" => "Door team" }
    )
    inactive_code = ReferralCode.create!(
      code: "ARCHIVE-BAR-1234",
      display_name: "Archived QA link",
      village: @village,
      created_by_user: @admin,
      active: false,
      metadata: { "source_type" => "outreach", "notes" => "Local QA Test" }
    )

    get "/api/v1/referral_codes", headers: auth_headers(@admin), as: :json
    assert_response :success
    assert_equal [ active_code.id ], response.parsed_body["referral_codes"].map { |row| row["id"] }

    get "/api/v1/referral_codes?status=inactive&q=local+qa&per_page=1", headers: auth_headers(@admin)
    assert_response :success
    assert_equal [ inactive_code.id ], response.parsed_body["referral_codes"].map { |row| row["id"] }
    assert_equal 1, response.parsed_body.dig("pagination", "total")
  end

  test "index can report signup link counts for the active quota period" do
    period = QuotaPeriod.create!(
      campaign_cycle: CampaignCycle.create!(
        name: "2026 DPG Organizing Cycle",
        cycle_type: "organizing",
        start_date: Date.current.beginning_of_year,
        end_date: Date.current.end_of_year,
        status: "active"
      ),
      name: "May Signup Push",
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      status: "open"
    )
    code = ReferralCode.create!(
      code: "PERIOD-BAR-1234",
      display_name: "Period link",
      village: @village,
      created_by_user: @admin,
      active: true,
      metadata: { "source_type" => "village" }
    )
    Supporter.create!(
      first_name: "Period",
      last_name: "Signup",
      contact_number: "671-555-2026",
      village: @village,
      source: "qr_signup",
      attribution_method: "qr_self_signup",
      referral_code: code,
      quota_period: period,
      leader_code: code.code,
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )
    Supporter.create!(
      first_name: "Lifetime",
      last_name: "Signup",
      contact_number: "671-555-2027",
      village: @village,
      source: "qr_signup",
      attribution_method: "qr_self_signup",
      referral_code: code,
      leader_code: code.code,
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    get "/api/v1/referral_codes?quota_period_id=active", headers: auth_headers(@admin)

    assert_response :success
    row = response.parsed_body["referral_codes"].find { |item| item["id"] == code.id }
    assert_equal 2, row["signup_count"]
    assert_equal 1, row["period_signup_count"]
    assert_equal 2, row["lifetime_signup_count"]
    assert_equal period.id, response.parsed_body.dig("selected_quota_period", "id")
  end

  test "unused signup link can be deleted" do
    code = ReferralCode.create!(
      code: "UNUSED-BAR-1234",
      display_name: "Unused link",
      village: @village,
      created_by_user: @admin,
      active: true,
      metadata: { "source_type" => "village" }
    )

    assert_difference -> { ReferralCode.count }, -1 do
      delete "/api/v1/referral_codes/#{code.id}", headers: auth_headers(@admin), as: :json
    end

    assert_response :success
    assert_equal true, response.parsed_body["deleted"]
  end

  test "used signup link is archived instead of deleted" do
    code = ReferralCode.create!(
      code: "USED-BAR-1234",
      display_name: "Used link",
      village: @village,
      created_by_user: @admin,
      active: true,
      metadata: { "source_type" => "village" }
    )
    supporter = Supporter.create!(
      first_name: "Linked",
      last_name: "Signup",
      contact_number: "671-555-1919",
      village: @village,
      source: "qr_signup",
      attribution_method: "qr_self_signup",
      referral_code: code,
      leader_code: code.code,
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    assert_no_difference -> { ReferralCode.count } do
      delete "/api/v1/referral_codes/#{code.id}", headers: auth_headers(@admin), as: :json
    end

    assert_response :success
    assert_equal false, response.parsed_body["deleted"]
    assert_equal false, code.reload.active
    assert_equal code.id, supporter.reload.referral_code_id
  end
end
