require "test_helper"

class Api::V1::SupportersControllerOutreachTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @admin = User.create!(
      clerk_id: "clerk-outreach-admin-#{SecureRandom.hex(4)}",
      email: "outreach-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Outreach Admin",
      role: "campaign_admin"
    )
    @leader = User.create!(
      clerk_id: "clerk-outreach-leader-#{SecureRandom.hex(4)}",
      email: "outreach-leader-#{SecureRandom.hex(4)}@example.com",
      name: "Outreach Leader",
      role: "block_leader",
      assigned_village_id: @village.id
    )
    @supporter = Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "671-555-1010",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
      registered_voter: false,
      registered_voter_status: "no",
      needs_voter_registration_help: true,
      status: "active"
    )
  end

  test "outreach queue includes latest contact attempt summary" do
    travel_to Time.zone.local(2026, 5, 12, 9, 0, 0) do
      SupporterContactAttempt.create!(
        supporter: @supporter,
        recorded_by_user: @admin,
        channel: "sms",
        outcome: "attempted",
        note: "Sent first registration reminder.",
        recorded_at: 2.hours.ago
      )
      SupporterContactAttempt.create!(
        supporter: @supporter,
        recorded_by_user: @leader,
        channel: "call",
        outcome: "reached",
        note: "Confirmed she wants help registering.",
        recorded_at: 30.minutes.ago
      )

      get "/api/v1/supporters/outreach", headers: auth_headers(@leader)
    end

    assert_response :success
    payload = JSON.parse(response.body)
    supporter = payload["supporters"].find { |row| row["id"] == @supporter.id }
    assert supporter, "Expected outreach response to include supporter #{@supporter.id}"

    latest_attempt = supporter["latest_contact_attempt"]

    assert_equal "call", latest_attempt["channel"]
    assert_equal "reached", latest_attempt["outcome"]
    assert_equal "Confirmed she wants help registering.", latest_attempt["note"]
    assert_equal "Outreach Leader", latest_attempt["recorded_by_name"]
  end

  test "outreach queue returns nil latest contact attempt when supporter has no attempts" do
    get "/api/v1/supporters/outreach", headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter = payload["supporters"].find { |row| row["id"] == @supporter.id }
    assert supporter, "Expected outreach response to include supporter #{@supporter.id}"
    assert_nil supporter["latest_contact_attempt"]
  end

  test "outreach queue treats canvass volunteer interest as support follow-up" do
    volunteer = Supporter.create!(
      first_name: "Volunteer",
      last_name: "Interest",
      contact_number: "671-555-2020",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
      volunteer_status: "interested",
      registered_voter: true,
      registered_voter_status: "yes",
      status: "active"
    )

    get "/api/v1/supporters/outreach", headers: auth_headers(@leader)

    assert_response :success
    row = response.parsed_body["supporters"].find { |supporter| supporter["id"] == volunteer.id }
    assert_not_nil row
    assert_equal true, row["needs_support_follow_up"]
    assert_equal true, row["support_follow_up_open"]
    assert_includes row["follow_up_reasons"], "Volunteer interest"
  end
end
