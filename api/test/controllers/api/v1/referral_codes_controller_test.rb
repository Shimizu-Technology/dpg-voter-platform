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
