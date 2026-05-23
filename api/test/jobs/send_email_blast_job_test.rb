require "test_helper"

class SendEmailBlastJobTest < ActiveSupport::TestCase
  test "skips cleanly when queued email blast no longer exists" do
    calls = 0
    original_send_blast = SupporterEmailService.method(:send_blast)
    SupporterEmailService.define_singleton_method(:send_blast) do |**_args|
      calls += 1
    end

    assert_nothing_raised do
      SendEmailBlastJob.perform_now(email_blast_id: 99_999)
    end
    assert_equal 0, calls
  ensure
    SupporterEmailService.define_singleton_method(:send_blast, original_send_blast) if original_send_blast
  end

  test "does not retry after email sending has started" do
    calls = 0
    original_send_blast = SupporterEmailService.method(:send_blast)

    SupporterEmailService.define_singleton_method(:send_blast) do |**_args|
      calls += 1
      raise ActiveRecord::StatementInvalid, "contact attempt insert failed"
    end

    assert_nothing_raised do
      SendEmailBlastJob.perform_now(subject: "DPG update", body: "Hello", filters: {}, initiated_by_user_id: nil)
    end
    assert_equal 1, calls
  ensure
    SupporterEmailService.define_singleton_method(:send_blast, original_send_blast) if original_send_blast
  end
end
