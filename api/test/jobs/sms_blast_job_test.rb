require "test_helper"

class SmsBlastJobTest < ActiveSupport::TestCase
  test "perform records SMS blast contact attempts for each provider result" do
    village = Village.create!(name: "Job Village")
    actor = User.create!(
      clerk_id: "clerk-sms-job",
      email: "sms-job@example.com",
      name: "SMS Job User",
      role: "campaign_admin"
    )
    sent_supporter = Supporter.create!(
      first_name: "Sent", last_name: "Person", print_name: "Sent Person",
      contact_number: "6715556000",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    failed_supporter = Supporter.create!(
      first_name: "Failed", last_name: "Person", print_name: "Failed Person",
      contact_number: "6715556001",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "pending",
      message: "DPG update",
      filters: {},
      total_recipients: 0,
      sent_count: 0,
      failed_count: 0,
      initiated_by: actor
    )

    fake_result = {
      sent: 1,
      failed: 1,
      results: [
        { to: "+16715556000", success: true, message_id: "msg-1", error: nil },
        { to: "+16715556001", success: false, message_id: nil, error: "INVALID_RECIPIENT" }
      ]
    }

    original_send_batch = ClicksendClient.method(:send_batch)
    ClicksendClient.define_singleton_method(:send_batch) { |_messages| fake_result }
    begin
      SmsBlastJob.perform_now(sms_blast_id: blast.id)
    ensure
      ClicksendClient.define_singleton_method(:send_batch, original_send_batch)
    end

    assert_equal "completed", blast.reload.status
    assert_equal 2, SupporterContactAttempt.where(recorded_by_user: actor, channel: "sms").count
    assert_equal "attempted", sent_supporter.supporter_contact_attempts.last.outcome
    assert_equal "unavailable", failed_supporter.supporter_contact_attempts.last.outcome
  end

  test "perform honors scoped village filters passed from recipient review" do
    included_village = Village.create!(name: "Included SMS Village")
    excluded_village = Village.create!(name: "Excluded SMS Village")
    actor = User.create!(
      clerk_id: "clerk-sms-scoped-job",
      email: "sms-scoped-job@example.com",
      name: "Scoped SMS Job User",
      role: "district_coordinator"
    )
    included = Supporter.create!(
      first_name: "Included", last_name: "Person", print_name: "Included Person",
      contact_number: "6715556100",
      village: included_village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    excluded = Supporter.create!(
      first_name: "Excluded", last_name: "Person", print_name: "Excluded Person",
      contact_number: "6715556101",
      village: excluded_village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "pending",
      message: "Scoped DPG update",
      filters: { "scoped_village_ids" => [ included_village.id ] },
      total_recipients: 0,
      sent_count: 0,
      failed_count: 0,
      initiated_by: actor
    )

    fake_result = {
      sent: 1,
      failed: 0,
      results: [
        { to: "+16715556100", success: true, message_id: "msg-2", error: nil }
      ]
    }

    original_send_batch = ClicksendClient.method(:send_batch)
    ClicksendClient.define_singleton_method(:send_batch) { |_messages| fake_result }
    begin
      SmsBlastJob.perform_now(sms_blast_id: blast.id)
    ensure
      ClicksendClient.define_singleton_method(:send_batch, original_send_batch)
    end

    assert_equal 1, blast.reload.total_recipients
    assert_equal 1, included.supporter_contact_attempts.count
    assert_equal 0, excluded.supporter_contact_attempts.count
  end

  test "perform records attempts for supporters sharing a phone number" do
    village = Village.create!(name: "Shared Phone Village")
    actor = User.create!(
      clerk_id: "clerk-sms-shared-phone",
      email: "sms-shared-phone@example.com",
      name: "Shared Phone SMS User",
      role: "campaign_admin"
    )
    first_supporter = Supporter.create!(
      first_name: "First", last_name: "Shared", print_name: "First Shared",
      contact_number: "6715556200",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    second_supporter = Supporter.create!(
      first_name: "Second", last_name: "Shared", print_name: "Second Shared",
      contact_number: "(671) 555-6200",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "pending",
      message: "Shared phone DPG update",
      filters: {},
      total_recipients: 0,
      sent_count: 0,
      failed_count: 0,
      initiated_by: actor
    )

    fake_result = {
      sent: 2,
      failed: 0,
      results: [
        { to: "+16715556200", success: true, message_id: "msg-shared-1", error: nil },
        { to: "+16715556200", success: true, message_id: "msg-shared-2", error: nil }
      ]
    }

    original_send_batch = ClicksendClient.method(:send_batch)
    ClicksendClient.define_singleton_method(:send_batch) { |_messages| fake_result }
    begin
      SmsBlastJob.perform_now(sms_blast_id: blast.id)
    ensure
      ClicksendClient.define_singleton_method(:send_batch, original_send_batch)
    end

    assert_equal 1, first_supporter.supporter_contact_attempts.where(channel: "sms").count
    assert_equal 1, second_supporter.supporter_contact_attempts.where(channel: "sms").count
  end

  test "perform matches reordered provider results by phone number" do
    village = Village.create!(name: "Reordered Result Village")
    actor = User.create!(
      clerk_id: "clerk-sms-reordered",
      email: "sms-reordered@example.com",
      name: "Reordered SMS User",
      role: "campaign_admin"
    )
    sent_supporter = Supporter.create!(
      first_name: "Sent", last_name: "Reordered", print_name: "Sent Reordered",
      contact_number: "6715556300",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    failed_supporter = Supporter.create!(
      first_name: "Failed", last_name: "Reordered", print_name: "Failed Reordered",
      contact_number: "6715556301",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "pending",
      message: "Reordered result DPG update",
      filters: {},
      total_recipients: 0,
      sent_count: 0,
      failed_count: 0,
      initiated_by: actor
    )

    fake_result = {
      sent: 1,
      failed: 1,
      results: [
        { to: "+16715556301", success: false, message_id: nil, error: "INVALID_RECIPIENT" },
        { to: "+16715556300", success: true, message_id: "msg-reordered-1", error: nil }
      ]
    }

    original_send_batch = ClicksendClient.method(:send_batch)
    ClicksendClient.define_singleton_method(:send_batch) { |_messages| fake_result }
    begin
      SmsBlastJob.perform_now(sms_blast_id: blast.id)
    ensure
      ClicksendClient.define_singleton_method(:send_batch, original_send_batch)
    end

    assert_equal "attempted", sent_supporter.supporter_contact_attempts.last.outcome
    assert_equal "unavailable", failed_supporter.supporter_contact_attempts.last.outcome
  end

  test "perform completes when contact attempt logging fails after SMS send" do
    village = Village.create!(name: "Logging Failure Village")
    actor = User.create!(
      clerk_id: "clerk-sms-log-failure",
      email: "sms-log-failure@example.com",
      name: "SMS Log Failure User",
      role: "campaign_admin"
    )
    Supporter.create!(
      first_name: "Logging", last_name: "Failure", print_name: "Logging Failure",
      contact_number: "6715556400",
      village: village,
      source: "staff_entry",
      opt_in_text: true,
      status: "active"
    )
    blast = SmsBlast.create!(
      status: "pending",
      message: "Logging failure DPG update",
      filters: {},
      total_recipients: 0,
      sent_count: 0,
      failed_count: 0,
      initiated_by: actor
    )

    fake_result = {
      sent: 1,
      failed: 0,
      results: [
        { to: "+16715556400", success: true, message_id: "msg-log-failure", error: nil }
      ]
    }

    original_send_batch = ClicksendClient.method(:send_batch)
    original_insert_all = SupporterContactAttempt.method(:insert_all!)
    ClicksendClient.define_singleton_method(:send_batch) { |_messages| fake_result }
    SupporterContactAttempt.define_singleton_method(:insert_all!) do |_attempts|
      raise ActiveRecord::StatementInvalid, "contact attempt insert failed"
    end

    begin
      SmsBlastJob.perform_now(sms_blast_id: blast.id)
    ensure
      ClicksendClient.define_singleton_method(:send_batch, original_send_batch)
      SupporterContactAttempt.define_singleton_method(:insert_all!, original_insert_all)
    end

    assert_equal "completed", blast.reload.status
    assert_equal 1, blast.sent_count
    assert_equal 0, blast.failed_count
  end
end
