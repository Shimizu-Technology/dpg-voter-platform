require "test_helper"

class Api::V1::CampaignInfoControllerTest < ActionDispatch::IntegrationTest
  test "show includes configurable thank-you reminder fields" do
    Campaign.create!(
      name: "Public Campaign",
      election_year: 2026,
      status: "active",
      signup_share_prompt: "Finish signing up, then share this form with another supporter.",
      thank_you_share_prompt: "Share this signup link with neighbors who want to support Josh and Tina.",
      primary_election_date: Date.new(2026, 8, 1),
      general_election_date: Date.new(2026, 11, 3)
    )

    get "/api/v1/campaign_info"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Public Campaign", payload["name"]
    assert_equal "Finish signing up, then share this form with another supporter.", payload["signup_share_prompt"]
    assert_equal "Share this signup link with neighbors who want to support Josh and Tina.", payload["thank_you_share_prompt"]
    assert_equal "2026-08-01", payload["primary_election_date"]
    assert_equal "2026-11-03", payload["general_election_date"]
  end
end
