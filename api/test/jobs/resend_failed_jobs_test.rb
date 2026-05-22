require "test_helper"

class ResendFailedJobsTest < ActiveJob::TestCase
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
