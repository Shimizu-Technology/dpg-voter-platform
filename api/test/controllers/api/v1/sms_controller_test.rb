require "test_helper"

class Api::V1::SmsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @leader = User.create!(
      clerk_id: "clerk-leader",
      email: "leader@example.com",
      name: "Leader",
      role: "block_leader"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator",
      email: "coordinator@example.com",
      name: "Coordinator",
      role: "district_coordinator"
    )
  end

  test "block leader cannot send test sms" do
    post "/api/v1/sms/send",
      params: { phone: "6715551234", message: "test" },
      headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "coordinator_access_required", payload["code"]
  end

  test "coordinator can queue blast" do
    supporter = Supporter.create!(
      first_name: "Blast", last_name: "Target", print_name: "Blast Target",
      contact_number: "6715552000",
      village: Village.create!(name: "Blast Village"),
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )

    with_live_outreach_enabled do
      assert_enqueued_with(job: SmsBlastJob) do
        post "/api/v1/sms/blast",
          params: { message: "DPG update", recipient_reviewed: true, expected_recipient_count: 1 },
          headers: auth_headers(@coordinator)
      end
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
    assert_equal 1, payload["total_targeted"]
    assert_equal supporter.id, Supporter.find(supporter.id).id
  end

  test "coordinator can dry run blast" do
    village = Village.create!(name: "Dry Run Village")
    Supporter.create!(
      first_name: "Preview", last_name: "Recipient", print_name: "Preview Recipient",
      contact_number: "6715553000",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )

    post "/api/v1/sms/blast",
      params: { message: "DPG update", dry_run: "true" },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["dry_run"]
    assert_equal 1, payload["recipient_count"]
    assert_equal "Preview Recipient", payload["recipients"].first["name"]
    assert_enqueued_jobs 0
  end

  test "coordinator live blast requires reviewed recipient count" do
    Supporter.create!(
      first_name: "Needs", last_name: "Review", print_name: "Needs Review",
      contact_number: "6715554000",
      village: Village.create!(name: "Review Village"),
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )

    with_live_outreach_enabled do
      post "/api/v1/sms/blast",
        params: { message: "DPG update", recipient_reviewed: true, expected_recipient_count: 99 },
        headers: auth_headers(@coordinator)
    end

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "recipient_review_required", payload["code"]
    assert_equal 1, payload.dig("details", "current_recipient_count")
    assert_enqueued_jobs 0
  end

  test "coordinator blast validates message with standard error envelope" do
    post "/api/v1/sms/blast",
      params: { message: "" },
      headers: auth_headers(@coordinator)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "Message is required", payload["error"]
    assert_equal "sms_message_required", payload["code"]
  end

  test "coordinator live blast is blocked by default" do
    with_live_outreach_disabled do
      post "/api/v1/sms/blast",
        params: { message: "DPG update" },
        headers: auth_headers(@coordinator)
    end

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "live_outreach_disabled", payload["code"]
  end

  private

  def with_live_outreach_enabled
    previous = ENV["DPG_LIVE_OUTREACH_ENABLED"]
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = "true"
    yield
  ensure
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = previous
  end

  def with_live_outreach_disabled
    previous = ENV["DPG_LIVE_OUTREACH_ENABLED"]
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = "false"
    yield
  ensure
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = previous
  end
end
