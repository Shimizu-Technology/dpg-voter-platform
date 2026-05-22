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

  test "coordinator can view and sync sms delivery receipts" do
    village = Village.create!(name: "SMS Delivery Village")
    supporter = Supporter.create!(
      first_name: "Delivery", last_name: "Target", print_name: "Delivery Target",
      contact_number: "6715556000",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "completed",
      message: "DPG update",
      total_recipients: 1,
      sent_count: 1,
      initiated_by: @coordinator
    )
    delivery = OutreachDelivery.create!(
      channel: "sms",
      sms_blast: blast,
      supporter: supporter,
      recipient: "+16715556000",
      provider: "clicksend",
      provider_message_id: "MSG-1",
      status: "sent"
    )

    get "/api/v1/sms/blasts/#{blast.id}/deliveries", headers: auth_headers(@coordinator)
    assert_response :success
    assert_equal delivery.id, response.parsed_body["deliveries"].first["id"]

    original = ClicksendClient.method(:sms_receipt)
    ClicksendClient.define_singleton_method(:sms_receipt) do |_message_id|
      { success: true, receipt: { "status_code" => 201, "status_text" => "Success: Message received on handset." } }
    end

    assert_enqueued_with(job: SmsSyncReceiptsJob) do
      post "/api/v1/sms/blasts/#{blast.id}/sync_receipts", headers: auth_headers(@coordinator)
    end
    assert_response :accepted
    assert_equal "sent", delivery.reload.status

    perform_enqueued_jobs
    assert_equal "delivered", delivery.reload.status
  ensure
    ClicksendClient.define_singleton_method(:sms_receipt, original) if original
  end

  test "resend failed sms does not resend the same original twice" do
    village = Village.create!(name: "SMS Resend Village")
    supporter = Supporter.create!(
      first_name: "Retry", last_name: "Target", print_name: "Retry Target",
      contact_number: "6715556100",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(status: "completed", message: "DPG retry", total_recipients: 1, failed_count: 1, initiated_by: @coordinator)
    original_delivery = OutreachDelivery.create!(
      channel: "sms",
      sms_blast: blast,
      supporter: supporter,
      recipient: "+16715556100",
      provider: "clicksend",
      status: "failed"
    )

    with_live_outreach_enabled do
      assert_enqueued_with(job: SmsResendFailedJob) do
        post "/api/v1/sms/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      end
      assert_response :accepted
      post "/api/v1/sms/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      assert_response :success
    end

    assert_equal 1, enqueued_jobs.count { |job| job[:job] == SmsResendFailedJob }
    assert_equal 1, original_delivery.resends.count
    assert_equal "queued", original_delivery.resends.first.status
  end

  test "sms resend failed job sends queued resend deliveries" do
    village = Village.create!(name: "SMS Async Resend Village")
    supporter = Supporter.create!(
      first_name: "Async", last_name: "Retry", print_name: "Async Retry",
      contact_number: "6715556150",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(status: "completed", message: "DPG retry", total_recipients: 1, failed_count: 1, initiated_by: @coordinator)
    original_delivery = OutreachDelivery.create!(
      channel: "sms",
      sms_blast: blast,
      supporter: supporter,
      recipient: "+16715556150",
      provider: "clicksend",
      status: "failed"
    )

    original = ClicksendClient.method(:send_batch)
    ClicksendClient.define_singleton_method(:send_batch) do |messages|
      { sent: messages.size, failed: 0, results: messages.map { |message| { to: message[:to], supporter_id: message[:supporter_id], success: true, message_id: "sms-resent-async", error: nil } } }
    end

    with_live_outreach_enabled do
      perform_enqueued_jobs do
        post "/api/v1/sms/blasts/#{blast.id}/resend_failed", headers: auth_headers(@coordinator)
      end
    end

    assert_response :accepted
    resend = original_delivery.resends.first
    assert_equal "sent", resend.status
    assert_equal "sms-resent-async", resend.provider_message_id
  ensure
    ClicksendClient.define_singleton_method(:send_batch, original) if original
  end

  test "sms resend failed job sends queued deliveries in safe clicksend batches" do
    village = Village.create!(name: "SMS Batched Resend Village")
    blast = SmsBlast.create!(status: "completed", message: "DPG retry", total_recipients: 2, failed_count: 2, initiated_by: @coordinator)
    deliveries = 2.times.map do |idx|
      supporter = Supporter.create!(
        first_name: "Batch", last_name: "Retry #{idx}", print_name: "Batch Retry #{idx}",
        contact_number: "67155562#{idx.to_s.rjust(2, '0')}",
        village: village,
        source: "staff_entry",
        opt_in_text: true,
        status: "active"
      )
      OutreachDelivery.create!(
        channel: "sms",
        sms_blast: blast,
        supporter: supporter,
        resend_of: OutreachDelivery.create!(
          channel: "sms",
          sms_blast: blast,
          supporter: supporter,
          recipient: supporter.contact_number,
          provider: "clicksend",
          status: "failed"
        ),
        recipient: supporter.contact_number,
        provider: "clicksend",
        status: "queued"
      )
    end

    previous_batch_size = SmsResendFailedJob::BATCH_SIZE
    previous_batch_delay = SmsResendFailedJob::BATCH_DELAY
    SmsResendFailedJob.send(:remove_const, :BATCH_SIZE)
    SmsResendFailedJob.const_set(:BATCH_SIZE, 1)
    SmsResendFailedJob.send(:remove_const, :BATCH_DELAY)
    SmsResendFailedJob.const_set(:BATCH_DELAY, 0)

    original = ClicksendClient.method(:send_batch)
    batch_sizes = []
    ClicksendClient.define_singleton_method(:send_batch) do |messages|
      batch_sizes << messages.size
      { sent: messages.size, failed: 0, results: messages.map { |message| { to: message[:to], supporter_id: message[:supporter_id], success: true, message_id: "sms-batch-#{batch_sizes.size}", error: nil } } }
    end

    SmsResendFailedJob.perform_now(delivery_ids: deliveries.map(&:id), recorded_by_user_id: @coordinator.id)

    assert_equal [ 1, 1 ], batch_sizes
    assert deliveries.all? { |delivery| delivery.reload.status == "sent" }
  ensure
    ClicksendClient.define_singleton_method(:send_batch, original) if original
    SmsResendFailedJob.send(:remove_const, :BATCH_SIZE)
    SmsResendFailedJob.const_set(:BATCH_SIZE, previous_batch_size)
    SmsResendFailedJob.send(:remove_const, :BATCH_DELAY)
    SmsResendFailedJob.const_set(:BATCH_DELAY, previous_batch_delay)
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
