require "test_helper"

class SupporterEmailServiceTest < ActiveSupport::TestCase
  test "send blast does not record false failure when delivery tracking fails after provider send" do
    previous_api_key = ENV["RESEND_API_KEY"]
    previous_from = ENV["RESEND_FROM_EMAIL"]
    ENV["RESEND_API_KEY"] = "test-resend-key"
    ENV["RESEND_FROM_EMAIL"] = "dpg@example.com"

    village = Village.create!(name: "Email Service Village")
    supporter = Supporter.create!(
      first_name: "Tracked",
      last_name: "Recipient",
      print_name: "Tracked Recipient",
      contact_number: "6715557300",
      email: "tracked@example.com",
      village: village,
      source: "staff_entry",
      opt_in_email: true,
      status: "active"
    )
    user = User.create!(clerk_id: "clerk-email-service", email: "email-service@example.com", name: "Email Service", role: "district_coordinator")
    blast = EmailBlast.create!(status: "sending", subject: "DPG update", body: "Hello", total_recipients: 1, initiated_by: user)

    with_stubbed_singleton_method(Resend::Emails, :send, ->(_payload) { { id: "email-sent-before-db-error" } }) do
      with_stubbed_singleton_method(OutreachDelivery, :create!, ->(**_attrs) { raise ActiveRecord::StatementInvalid, "database unavailable" }) do
        result = SupporterEmailService.send_blast(
          subject: "DPG update",
          body_html: "Hello {first_name}",
          supporters: Supporter.where(id: supporter.id),
          email_blast: blast
        )

        assert_equal 1, result[:sent]
        assert_equal 0, result[:failed]
        assert_match(/delivery tracking failed after send/, result[:errors].first)
      end
    end
  ensure
    ENV["RESEND_API_KEY"] = previous_api_key
    ENV["RESEND_FROM_EMAIL"] = previous_from
  end
end
