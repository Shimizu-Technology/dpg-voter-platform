# frozen_string_literal: true

require "test_helper"

class ClicksendClientTest < ActiveSupport::TestCase
  test "formats Guam phone numbers for ClickSend" do
    assert_equal "+16714830219", ClicksendClient.send(:format_sms_recipient, "6714830219")
    assert_equal "+16714830219", ClicksendClient.send(:format_sms_recipient, "(671) 483-0219")
    assert_equal "+16714830219", ClicksendClient.send(:format_sms_recipient, "+1 671 483 0219")
    assert_equal "+16714830219", ClicksendClient.send(:format_sms_recipient, "4830219")
  end

  test "rejects unsupported phone numbers before sending to ClickSend" do
    assert_nil ClicksendClient.send(:format_sms_recipient, "12345")
    assert_nil ClicksendClient.send(:format_sms_recipient, "671483021")
  end
end
