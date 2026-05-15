# frozen_string_literal: true

require "test_helper"
require "cgi"

class ReferralCodesTest < ActionDispatch::IntegrationTest
  def setup
    super
    @campaign = Campaign.create!(name: "Democratic Party of Guam", election_year: 2026, status: "active")
    @village = Village.create!(name: "Tamuning #{SecureRandom.hex(3)}")
    @admin = User.create!(
      clerk_id: "clerk-admin-#{SecureRandom.hex(4)}",
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      name: "Admin User",
      role: "campaign_admin"
    )
  end

  test "admin creates signup link and public signup stores attribution" do
    post "/api/v1/referral_codes",
      params: {
        referral_code: {
          display_name: "Tamuning Canvass",
          source_type: "village",
          village_id: @village.id,
          notes: "Saturday outreach"
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :created
    payload = JSON.parse(response.body)
    code = payload.dig("referral_code", "code")
    assert code.present?
    assert_match %r{/signup/#{Regexp.escape(code)}\z}, payload.dig("referral_code", "signup_url")

    assert_difference -> { Supporter.where(source: "qr_signup").count }, 1 do
      post "/api/v1/supporters?leader_code=#{CGI.escape(code)}",
        params: {
          supporter: {
            first_name: "Source",
            last_name: "Signup",
            contact_number: "6715550101",
            email: "source-signup@example.com",
            street_address: "1 Source Lane",
            village_id: @village.id,
            registered_voter_status: "not_sure"
          }
        },
        as: :json
    end

    assert_response :created
    supporter_payload = JSON.parse(response.body).fetch("supporter")
    assert_equal "qr_signup", supporter_payload.fetch("source")
    assert_equal "qr_self_signup", supporter_payload.fetch("attribution_method")
    assert_equal code, supporter_payload.fetch("leader_code")
    assert_equal "Tamuning Canvass", supporter_payload.fetch("referral_display_name")

    get "/api/v1/referral_codes", headers: auth_headers(@admin)
    assert_response :success
    row = JSON.parse(response.body).fetch("referral_codes").find { |item| item["code"] == code }
    assert_equal 1, row.fetch("signup_count")
  end

  test "inactive signup link is not applied to new public signup" do
    referral = ReferralCode.create!(
      display_name: "Inactive Link",
      code: "INACTIVE-#{SecureRandom.hex(2).upcase}",
      village: @village,
      active: false,
      metadata: { "source_type" => "custom" }
    )

    post "/api/v1/supporters?leader_code=#{CGI.escape(referral.code)}",
      params: {
        supporter: {
          first_name: "Plain",
          last_name: "Signup",
          contact_number: "6715550202",
          email: "plain-signup@example.com",
          street_address: "2 Source Lane",
          village_id: @village.id,
          registered_voter_status: "not_sure"
        }
      },
      as: :json

    assert_response :created
    supporter_payload = JSON.parse(response.body).fetch("supporter")
    assert_equal "public_signup", supporter_payload.fetch("source")
    assert_nil supporter_payload.fetch("leader_code")
    assert_nil supporter_payload.fetch("referral_code_id")
  end

  test "create returns json error when village does not exist" do
    post "/api/v1/referral_codes",
      params: {
        referral_code: {
          display_name: "Unknown Village Link",
          source_type: "village",
          village_id: Village.maximum(:id).to_i + 10_000
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :not_found
    payload = JSON.parse(response.body)
    assert_equal "Village not found", payload.fetch("error")
    assert_equal "village_not_found", payload.fetch("code")
  end

  test "create returns json error when assigned user does not exist" do
    post "/api/v1/referral_codes",
      params: {
        referral_code: {
          display_name: "Unknown User Link",
          source_type: "canvasser",
          village_id: @village.id,
          assigned_user_id: User.maximum(:id).to_i + 10_000
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :not_found
    payload = JSON.parse(response.body)
    assert_equal "Assigned user not found", payload.fetch("error")
    assert_equal "user_not_found", payload.fetch("code")
  end
end
