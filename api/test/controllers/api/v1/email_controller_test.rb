require "test_helper"

class Api::V1::EmailControllerTest < ActionDispatch::IntegrationTest
  setup do
    @leader = User.create!(
      clerk_id: "clerk-email-leader",
      email: "email-leader@example.com",
      name: "Email Leader",
      role: "block_leader"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-email-coordinator",
      email: "email-coordinator@example.com",
      name: "Email Coordinator",
      role: "district_coordinator"
    )
  end

  test "block leader cannot queue email blast" do
    post "/api/v1/email/blast",
      params: { subject: "DPG update", body: "Hello" },
      headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "coordinator_access_required", payload["code"]
  end

  test "coordinator can dry run email blast with recipient review sample" do
    Supporter.create!(
      first_name: "Email", last_name: "Recipient", print_name: "Email Recipient",
      contact_number: "6715555000",
      email: "recipient@example.com",
      village: Village.create!(name: "Email Village"),
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )

    post "/api/v1/email/blast",
      params: { subject: "Hafa adai {first_name}", body: "Hello {first_name}", dry_run: "true" },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["dry_run"]
    assert_equal 1, payload["recipient_count"]
    assert_equal "Email Recipient", payload["recipients"].first["name"]
    assert_equal "Hafa adai Maria", payload["preview_subject"]
    assert_enqueued_jobs 0
  end

  test "coordinator live email blast requires reviewed recipient count" do
    Supporter.create!(
      first_name: "Email", last_name: "Review", print_name: "Email Review",
      contact_number: "6715555001",
      email: "review@example.com",
      village: Village.create!(name: "Email Review Village"),
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )

    with_live_outreach_enabled do
      post "/api/v1/email/blast",
        params: { subject: "DPG update", body: "Hello", recipient_reviewed: true, expected_recipient_count: 9 },
        headers: auth_headers(@coordinator)
    end

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "recipient_review_required", payload["code"]
    assert_equal 1, payload.dig("details", "current_recipient_count")
    assert_enqueued_jobs 0
  end

  test "coordinator can queue reviewed email blast" do
    Supporter.create!(
      first_name: "Email", last_name: "Target", print_name: "Email Target",
      contact_number: "6715555002",
      email: "target@example.com",
      village: Village.create!(name: "Email Target Village"),
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )

    with_live_outreach_enabled do
      assert_enqueued_with(job: SendEmailBlastJob) do
        post "/api/v1/email/blast",
          params: { subject: "DPG update", body: "Hello", recipient_reviewed: true, expected_recipient_count: 1 },
          headers: auth_headers(@coordinator)
      end
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
    assert_equal 1, payload["total_targeted"]
  end

  private

  def with_live_outreach_enabled
    previous = ENV["DPG_LIVE_OUTREACH_ENABLED"]
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = "true"
    yield
  ensure
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = previous
  end
end
