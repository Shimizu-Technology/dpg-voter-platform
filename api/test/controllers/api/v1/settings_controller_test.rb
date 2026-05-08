require "test_helper"

class Api::V1::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      clerk_id: "clerk-settings-admin",
      email: "settings-admin@example.com",
      name: "Settings Admin",
      role: "campaign_admin"
    )
    @campaign = Campaign.create!(
      name: "Settings Campaign",
      election_year: 2026,
      status: "active"
    )
  end

  test "show includes public thank-you reminder settings" do
    @campaign.update!(
      signup_share_prompt: "Finish signing up, then send this form to another supporter you know.",
      thank_you_share_prompt: "Send this signup form to friends and family who support the campaign.",
      primary_election_date: Date.new(2026, 8, 1),
      general_election_date: Date.new(2026, 11, 3)
    )

    get "/api/v1/settings", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Finish signing up, then send this form to another supporter you know.", payload["signup_share_prompt"]
    assert_equal "Send this signup form to friends and family who support the campaign.", payload["thank_you_share_prompt"]
    assert_equal "2026-08-01", payload["primary_election_date"]
    assert_equal "2026-11-03", payload["general_election_date"]
  end

  test "update persists public thank-you reminder settings" do
    patch "/api/v1/settings",
      params: {
        signup_share_prompt: "Complete your response, then share this form with another Josh and Tina supporter.",
        thank_you_share_prompt: "Please share this link with other Guam voters who want campaign updates.",
        primary_election_date: "2026-08-01",
        general_election_date: "2026-11-03"
      },
      headers: auth_headers(@admin)

    assert_response :success
    @campaign.reload
    assert_equal "Complete your response, then share this form with another Josh and Tina supporter.", @campaign.signup_share_prompt
    assert_equal "Please share this link with other Guam voters who want campaign updates.", @campaign.thank_you_share_prompt
    assert_equal Date.new(2026, 8, 1), @campaign.primary_election_date
    assert_equal Date.new(2026, 11, 3), @campaign.general_election_date
  end
end
