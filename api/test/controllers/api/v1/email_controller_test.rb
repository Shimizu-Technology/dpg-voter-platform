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
    assert EmailBlast.exists?(payload["blast_id"])
  end

  test "email resend failed does not resend the same original twice" do
    village = Village.create!(name: "Email Resend Village")
    supporter = Supporter.create!(
      first_name: "Email", last_name: "Retry", print_name: "Email Retry",
      contact_number: "6715557100",
      email: "retry@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG retry", body: "Hello {first_name}", initiated_by: @coordinator)
    original_delivery = OutreachDelivery.create!(
      channel: "email",
      email_blast: blast,
      supporter: supporter,
      recipient: supporter.email,
      provider: "resend",
      status: "failed"
    )

    with_live_outreach_enabled do
      assert_enqueued_with(job: EmailResendFailedJob) do
        post "/api/v1/email/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      end
      assert_response :accepted
      post "/api/v1/email/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      assert_response :success
    end

    assert_equal 1, enqueued_jobs.count { |job| job[:job] == EmailResendFailedJob }
    assert_equal 1, original_delivery.resends.count
    assert_equal "queued", original_delivery.resends.first.status
  end

  test "email resend failed job sends queued resend deliveries" do
    village = Village.create!(name: "Email Async Resend Village")
    supporter = Supporter.create!(
      first_name: "Async", last_name: "Retry", print_name: "Async Retry",
      contact_number: "6715557150",
      email: "async-retry@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG retry", body: "Hello {first_name}", initiated_by: @coordinator)
    original_delivery = OutreachDelivery.create!(
      channel: "email",
      email_blast: blast,
      supporter: supporter,
      recipient: supporter.email,
      provider: "resend",
      status: "failed"
    )

    original = Resend::Emails.method(:send)
    Resend::Emails.define_singleton_method(:send) { |_payload| { id: "email-resent-async" } }

    with_live_outreach_enabled do
      perform_enqueued_jobs do
        post "/api/v1/email/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      end
    end

    assert_response :accepted
    resend = original_delivery.resends.first
    assert_equal "sent", resend.status
    assert_equal "email-resent-async", resend.provider_message_id
  ensure
    Resend::Emails.define_singleton_method(:send, original) if original
  end

  test "resend webhook updates email delivery status" do
    village = Village.create!(name: "Webhook Village")
    supporter = Supporter.create!(
      first_name: "Webhook", last_name: "Target", print_name: "Webhook Target",
      contact_number: "6715557000",
      email: "webhook@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG update", body: "Hello", initiated_by: @coordinator)
    delivery = OutreachDelivery.create!(
      channel: "email",
      email_blast: blast,
      supporter: supporter,
      recipient: supporter.email,
      provider: "resend",
      provider_message_id: "email-1",
      status: "sent"
    )

    post "/api/v1/email/webhooks/resend",
      params: {
        type: "email.delivered",
        created_at: Time.current.iso8601,
        data: { email_id: "email-1" }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_equal "delivered", delivery.reload.status
  end

  test "resend webhook ignores events without email id" do
    village = Village.create!(name: "Blank Webhook Village")
    supporter = Supporter.create!(
      first_name: "Blank", last_name: "Webhook", print_name: "Blank Webhook",
      contact_number: "6715557200",
      email: "blank-webhook@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG update", body: "Hello", initiated_by: @coordinator)
    delivery = OutreachDelivery.create!(
      channel: "email",
      email_blast: blast,
      supporter: supporter,
      recipient: supporter.email,
      provider: "resend",
      provider_message_id: nil,
      status: "failed"
    )

    post "/api/v1/email/webhooks/resend",
      params: {
        type: "email.delivered",
        created_at: Time.current.iso8601,
        data: {}
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_equal "failed", delivery.reload.status
  end

  test "resend webhook rejects stale signed payloads" do
    previous_secret = ENV["RESEND_WEBHOOK_SIGNING_SECRET"]
    secret_bytes = "test-secret-for-svix"
    ENV["RESEND_WEBHOOK_SIGNING_SECRET"] = "whsec_#{Base64.strict_encode64(secret_bytes)}"
    body = {
      type: "email.delivered",
      created_at: Time.current.iso8601,
      data: { email_id: "email-stale" }
    }.to_json
    timestamp = 10.minutes.ago.to_i.to_s
    svix_id = "msg_test"
    signed_payload = "#{svix_id}.#{timestamp}.#{body}"
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret_bytes, signed_payload))

    post "/api/v1/email/webhooks/resend",
      params: body,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "svix-id" => svix_id,
        "svix-timestamp" => timestamp,
        "svix-signature" => "v1,#{signature}"
      }

    assert_response :unauthorized
  ensure
    ENV["RESEND_WEBHOOK_SIGNING_SECRET"] = previous_secret
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
