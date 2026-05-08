require "test_helper"

class Api::V1::EmailControllerTest < ActionDispatch::IntegrationTest
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
    @village = Village.create!(name: "Test Village")
  end

  test "block leader cannot send email blast" do
    post "/api/v1/email/blast",
      params: { subject: "Test", body: "Hello" },
      headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "coordinator_access_required", payload["code"]
  end

  test "coordinator can get email status" do
    get "/api/v1/email/status", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.keys, "configured"
    assert_includes payload.keys, "from_email"
  end

  test "coordinator can queue email blast" do
    Supporter.create!(
      first_name: "Email", last_name: "Recipient", print_name: "Email Recipient",
      email: "test@example.com",
      contact_number: "6715551234",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    assert_enqueued_with(job: SendEmailBlastJob) do
      post "/api/v1/email/blast",
        params: { subject: "Campaign Update", body: "Hello supporters!" },
        headers: auth_headers(@coordinator)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["queued"]
    assert payload["total_targeted"].is_a?(Integer)
  end

  test "coordinator can dry run email blast" do
    Supporter.create!(
      first_name: "Email", last_name: "Recipient", print_name: "Email Recipient",
      email: "test@example.com",
      contact_number: "6715551234",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    post "/api/v1/email/blast",
      params: {
        subject: "Campaign Update",
        body: "Hello {first_name}!",
        dry_run: "true"
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["dry_run"]
    assert payload["recipient_count"].is_a?(Integer)
    assert payload["preview_subject"].is_a?(String)
    assert payload["preview_html"].is_a?(String)
    assert_enqueued_jobs 0
  end

  test "email blast validates subject and body" do
    post "/api/v1/email/blast",
      params: { subject: "", body: "" },
      headers: auth_headers(@coordinator)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "email_content_required", payload["code"]
    assert_match(/Subject and body are required/, payload["error"])
  end

  test "email blast filters by village" do
    other_village = Village.create!(name: "Other Village")

    Supporter.create!(
      first_name: "Target", last_name: "User", print_name: "Target User",
      email: "target@example.com",
      contact_number: "6715551111",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    Supporter.create!(
      first_name: "Other", last_name: "User", print_name: "Other User",
      email: "other@example.com",
      contact_number: "6715552222",
      opt_in_email: true,
      village: other_village,
      source: "staff_entry",
      status: "active"
    )

    post "/api/v1/email/blast",
      params: {
        subject: "Village Specific",
        body: "Hello!",
        village_id: @village.id,
        dry_run: "true"
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["recipient_count"]
  end

  test "email blast only includes opted in supporters" do
    Supporter.create!(
      first_name: "Opted", last_name: "In", print_name: "Opted In",
      email: "opted@example.com",
      contact_number: "6715551111",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    Supporter.create!(
      first_name: "Not", last_name: "Opted", print_name: "Not Opted",
      email: "notopted@example.com",
      contact_number: "6715552222",
      opt_in_email: false,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    post "/api/v1/email/blast",
      params: {
        subject: "Opt-in Test",
        body: "Hello!",
        dry_run: "true"
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["recipient_count"]
  end

  test "email blast excludes supporters without email" do
    Supporter.create!(
      first_name: "No", last_name: "Email", print_name: "No Email",
      email: nil,
      contact_number: "6715551234",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    post "/api/v1/email/blast",
      params: {
        subject: "Email Test",
        body: "Hello!",
        dry_run: "true"
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["recipient_count"]
  end

  test "email blast filters by motorcade_available" do
    Supporter.create!(
      first_name: "Motorcade", last_name: "Yes", print_name: "Motorcade Yes",
      email: "motor@example.com",
      contact_number: "6715551111",
      opt_in_email: true,
      motorcade_available: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    Supporter.create!(
      first_name: "Motorcade", last_name: "No", print_name: "Motorcade No",
      email: "nomotor@example.com",
      contact_number: "6715552222",
      opt_in_email: true,
      motorcade_available: false,
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    post "/api/v1/email/blast",
      params: {
        subject: "Motorcade",
        body: "Join us!",
        motorcade_available: "true",
        dry_run: "true"
      },
      headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["recipient_count"]
  end

  test "welcome email job is queued on supporter signup with opt_in_email" do
    assert_enqueued_with(job: SendWelcomeEmailJob) do
      post "/api/v1/supporters",
        params: {
          supporter: {
            first_name: "New",
            last_name: "Supporter",
            email: "new@example.com",
            opt_in_email: true,
            village_id: @village.id,
            contact_number: "6715551234"
          }
        }
    end

    assert_response :created
  end

  test "welcome email job is not queued when opt_in_email is false" do
    assert_no_enqueued_jobs do
      post "/api/v1/supporters",
        params: {
          supporter: {
            first_name: "New",
            last_name: "Supporter",
            email: "new@example.com",
            opt_in_email: false,
            village_id: @village.id,
            contact_number: "6715551234"
          }
        }
    end

    assert_response :created
  end
end
