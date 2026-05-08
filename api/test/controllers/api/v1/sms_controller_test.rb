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
    @campaign = Campaign.create!(name: "Test Campaign", election_year: Date.current.year, status: "active")
    @event = Event.create!(
      campaign: @campaign,
      name: "Test Event",
      event_type: "meeting",
      date: Date.current,
      status: "upcoming"
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

  test "block leader cannot send event notification" do
    post "/api/v1/sms/event_notify",
      params: { event_id: @event.id, type: "rsvp" },
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

    assert_enqueued_with(job: SmsBlastJob) do
      post "/api/v1/sms/blast",
        params: { message: "Campaign update" },
        headers: auth_headers(@coordinator)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
  end

  test "coordinator can dry run blast" do
    post "/api/v1/sms/blast",
      params: { message: "Campaign update", dry_run: "true" },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["dry_run"]
    assert_enqueued_jobs 0
  end

  test "coordinator event notify enqueues job" do
    assert_enqueued_with(job: EventNotifyJob) do
      post "/api/v1/sms/event_notify",
        params: { event_id: @event.id, type: "reminder" },
        headers: auth_headers(@coordinator)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
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
end
