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
    Supporter.create!(
      first_name: "Blast", last_name: "Target", print_name: "Blast Target",
      contact_number: "6715552000",
      village: Village.create!(name: "Blast Village"),
      source: "staff_entry",
      status: "active"
    )

    with_live_outreach_enabled do
      assert_enqueued_with(job: SmsBlastJob) do
        post "/api/v1/sms/blast",
          params: { message: "DPG update" },
          headers: auth_headers(@coordinator)
      end
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
  end

  test "coordinator can dry run blast" do
    post "/api/v1/sms/blast",
      params: { message: "DPG update", dry_run: "true" },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["dry_run"]
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
