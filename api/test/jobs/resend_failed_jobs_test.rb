require "test_helper"

class ResendFailedJobsTest < ActiveJob::TestCase
  test "sms receipt sync job throttles receipt lookups in batches" do
    user = User.create!(clerk_id: "clerk-sms-sync-job", email: "sms-sync-job@example.com", name: "SMS Sync Job", role: "district_coordinator")
    village = Village.create!(name: "SMS Sync Village")
    blast = SmsBlast.create!(status: "completed", message: "DPG update", total_recipients: 2, sent_count: 2, initiated_by: user)
    deliveries = 2.times.map do |idx|
      supporter = Supporter.create!(
        first_name: "Sync", last_name: "Recipient #{idx}", print_name: "Sync Recipient #{idx}",
        contact_number: "67155563#{idx.to_s.rjust(2, '0')}",
        village: village,
        source: "staff_entry",
        opt_in_text: true,
        status: "active"
      )
      OutreachDelivery.create!(
        channel: "sms",
        sms_blast: blast,
        supporter: supporter,
        recipient: supporter.contact_number,
        provider: "clicksend",
        provider_message_id: "MSG-#{idx}",
        status: "sent"
      )
    end

    previous_batch_size = SmsSyncReceiptsJob::BATCH_SIZE
    previous_batch_delay = SmsSyncReceiptsJob::BATCH_DELAY
    SmsSyncReceiptsJob.send(:remove_const, :BATCH_SIZE)
    SmsSyncReceiptsJob.const_set(:BATCH_SIZE, 1)
    SmsSyncReceiptsJob.send(:remove_const, :BATCH_DELAY)
    SmsSyncReceiptsJob.const_set(:BATCH_DELAY, 0)

    receipt_calls = []
    with_stubbed_singleton_method(ClicksendClient, :sms_receipt, lambda { |message_id|
      receipt_calls << message_id
      { success: true, receipt: { "status_code" => 201, "status_text" => "Success: Message received on handset." } }
    }) do
      SmsSyncReceiptsJob.perform_now(sms_blast_id: blast.id)
    end

    assert_equal deliveries.map(&:provider_message_id), receipt_calls
    assert deliveries.all? { |delivery| delivery.reload.status == "delivered" }
  ensure
    SmsSyncReceiptsJob.send(:remove_const, :BATCH_SIZE)
    SmsSyncReceiptsJob.const_set(:BATCH_SIZE, previous_batch_size)
    SmsSyncReceiptsJob.send(:remove_const, :BATCH_DELAY)
    SmsSyncReceiptsJob.const_set(:BATCH_DELAY, previous_batch_delay)
  end

  test "sms receipt sync job does not regress terminal delivery statuses" do
    user = User.create!(clerk_id: "clerk-sms-sync-terminal", email: "sms-sync-terminal@example.com", name: "SMS Sync Terminal", role: "district_coordinator")
    village = Village.create!(name: "SMS Sync Terminal Village")
    supporter = Supporter.create!(
      first_name: "Terminal", last_name: "Recipient", print_name: "Terminal Recipient",
      contact_number: "6715556399",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(status: "completed", message: "DPG update", total_recipients: 1, sent_count: 1, initiated_by: user)
    delivery = OutreachDelivery.create!(
      channel: "sms",
      sms_blast: blast,
      supporter: supporter,
      recipient: supporter.contact_number,
      provider: "clicksend",
      provider_message_id: "MSG-terminal",
      status: "delivered"
    )

    calls = 0
    with_stubbed_singleton_method(ClicksendClient, :sms_receipt, lambda { |_message_id|
      calls += 1
      { success: true, receipt: { "status_code" => 0, "status_text" => "Unknown" } }
    }) do
      SmsSyncReceiptsJob.perform_now(sms_blast_id: blast.id)
    end

    assert_equal 0, calls
    assert_equal "delivered", delivery.reload.status
  end

  test "sms resend job resets queued deliveries when batch send is interrupted" do
    user = User.create!(clerk_id: "clerk-sms-resend-job", email: "sms-resend-job@example.com", name: "SMS Resend Job", role: "district_coordinator")
    village = Village.create!(name: "SMS Job Village")
    supporter = Supporter.create!(
      first_name: "SMS", last_name: "Queued", print_name: "SMS Queued",
      contact_number: "6715556400",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(status: "completed", message: "DPG retry", total_recipients: 1, failed_count: 1, initiated_by: user)
    original = OutreachDelivery.create!(channel: "sms", sms_blast: blast, supporter: supporter, recipient: supporter.contact_number, provider: "clicksend", status: "failed")
    queued = OutreachDelivery.create!(channel: "sms", sms_blast: blast, supporter: supporter, resend_of: original, recipient: supporter.contact_number, provider: "clicksend", status: "queued")

    with_stubbed_singleton_method(ClicksendClient, :send_batch, ->(_messages) { raise StandardError, "timeout" }) do
      SmsResendFailedJob.perform_now(delivery_ids: [ queued.id ], recorded_by_user_id: user.id)
    end

    assert_equal "failed", queued.reload.status
    assert_match(/interrupted before completion/, queued.provider_status_text)
  end

  test "sms resend job marks queued delivery failed when clicksend returns no row" do
    user = User.create!(clerk_id: "clerk-sms-empty-result-job", email: "sms-empty-result-job@example.com", name: "SMS Empty Result Job", role: "district_coordinator")
    village = Village.create!(name: "SMS Empty Result Village")
    supporter = Supporter.create!(
      first_name: "SMS", last_name: "Missing", print_name: "SMS Missing",
      contact_number: "6715556450",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(status: "completed", message: "DPG retry", total_recipients: 1, failed_count: 1, initiated_by: user)
    original = OutreachDelivery.create!(channel: "sms", sms_blast: blast, supporter: supporter, recipient: supporter.contact_number, provider: "clicksend", status: "failed")
    queued = OutreachDelivery.create!(channel: "sms", sms_blast: blast, supporter: supporter, resend_of: original, recipient: supporter.contact_number, provider: "clicksend", status: "queued")

    with_stubbed_singleton_method(ClicksendClient, :send_batch, ->(_messages) { { sent: 0, failed: 0, results: [] } }) do
      SmsResendFailedJob.perform_now(delivery_ids: [ queued.id ], recorded_by_user_id: user.id)
    end

    assert_equal "failed", queued.reload.status
    assert_equal "ClickSend resend returned no result for this recipient", queued.provider_status_text
  end

  test "email resend job throttles resend work in batches" do
    previous_from = ENV["RESEND_FROM_EMAIL"]
    ENV["RESEND_FROM_EMAIL"] = "dpg@example.com"
    user = User.create!(clerk_id: "clerk-email-batch-job", email: "email-batch-job@example.com", name: "Email Batch Job", role: "district_coordinator")
    village = Village.create!(name: "Email Batch Village")
    blast = EmailBlast.create!(status: "completed", subject: "DPG retry", body: "Hello {first_name}", initiated_by: user)
    deliveries = 2.times.map do |idx|
      supporter = Supporter.create!(
        first_name: "Email", last_name: "Batch #{idx}", print_name: "Email Batch #{idx}",
        contact_number: "67155575#{idx.to_s.rjust(2, '0')}",
        email: "email-batch-#{idx}@example.com",
        village: village,
        source: "staff_entry",
        opt_in_email: true,
        status: "active"
      )
      original = OutreachDelivery.create!(channel: "email", email_blast: blast, supporter: supporter, recipient: supporter.email, provider: "resend", status: "failed")
      OutreachDelivery.create!(channel: "email", email_blast: blast, supporter: supporter, resend_of: original, recipient: supporter.email, provider: "resend", status: "queued")
    end

    previous_batch_size = EmailResendFailedJob::BATCH_SIZE
    previous_batch_delay = EmailResendFailedJob::BATCH_DELAY
    EmailResendFailedJob.send(:remove_const, :BATCH_SIZE)
    EmailResendFailedJob.const_set(:BATCH_SIZE, 1)
    EmailResendFailedJob.send(:remove_const, :BATCH_DELAY)
    EmailResendFailedJob.const_set(:BATCH_DELAY, 0)

    calls = []
    with_stubbed_singleton_method(Resend::Emails, :send, lambda { |payload|
      calls << payload[:to]
      { id: "email-batch-#{calls.size}" }
    }) do
      EmailResendFailedJob.perform_now(delivery_ids: deliveries.map(&:id), recorded_by_user_id: user.id)
    end

    assert_equal deliveries.map(&:recipient), calls
    assert deliveries.all? { |delivery| delivery.reload.status == "sent" }
  ensure
    ENV["RESEND_FROM_EMAIL"] = previous_from
    EmailResendFailedJob.send(:remove_const, :BATCH_SIZE)
    EmailResendFailedJob.const_set(:BATCH_SIZE, previous_batch_size)
    EmailResendFailedJob.send(:remove_const, :BATCH_DELAY)
    EmailResendFailedJob.const_set(:BATCH_DELAY, previous_batch_delay)
  end

  test "email resend job records provider failures as failed deliveries" do
    previous_from = ENV["RESEND_FROM_EMAIL"]
    ENV["RESEND_FROM_EMAIL"] = "dpg@example.com"
    user = User.create!(clerk_id: "clerk-email-resend-job", email: "email-resend-job@example.com", name: "Email Resend Job", role: "district_coordinator")
    village = Village.create!(name: "Email Job Village")
    supporter = Supporter.create!(
      first_name: "Email", last_name: "Queued", print_name: "Email Queued",
      contact_number: "6715557400",
      email: "queued@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    blast = EmailBlast.create!(status: "completed", subject: "DPG retry", body: "Hello", initiated_by: user)
    original = OutreachDelivery.create!(channel: "email", email_blast: blast, supporter: supporter, recipient: supporter.email, provider: "resend", status: "failed")
    queued = OutreachDelivery.create!(channel: "email", email_blast: blast, supporter: supporter, resend_of: original, recipient: supporter.email, provider: "resend", status: "queued")

    with_stubbed_singleton_method(Resend::Emails, :send, ->(_payload) { raise StandardError, "timeout" }) do
      EmailResendFailedJob.perform_now(delivery_ids: [ queued.id ], recorded_by_user_id: user.id)
    end

    assert_equal "failed", queued.reload.status
    assert_equal "timeout", queued.provider_status_text
  ensure
    ENV["RESEND_FROM_EMAIL"] = previous_from
  end
end
