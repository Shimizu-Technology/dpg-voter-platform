require "test_helper"

class SupporterEmailServiceTest < ActiveSupport::TestCase
  def setup
    @village = Village.create!(name: "Test Village")
    @supporter = Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      print_name: "Maria Cruz",
      email: "maria@example.com",
      contact_number: "6715551234",
      opt_in_email: true,
      village: @village,
      source: "staff_entry",
      status: "active"
    )
    @original_api_key = ENV["RESEND_API_KEY"]
    @original_from_email = ENV["RESEND_FROM_EMAIL"]
  end

  def teardown
    ENV["RESEND_API_KEY"] = @original_api_key
    ENV["RESEND_FROM_EMAIL"] = @original_from_email
    ENV["FRONTEND_URL"] = nil
  end

  test "configured? returns false when RESEND_API_KEY is missing" do
    ENV["RESEND_API_KEY"] = nil
    ENV["RESEND_FROM_EMAIL"] = nil
    assert_equal false, SupporterEmailService.configured?
  end

  test "configured? returns false when RESEND_FROM_EMAIL is missing" do
    ENV["RESEND_API_KEY"] = "test_key"
    ENV["RESEND_FROM_EMAIL"] = nil
    assert_equal false, SupporterEmailService.configured?
  end

  test "configured? returns true when both env vars are present" do
    ENV["RESEND_API_KEY"] = "test_key"
    ENV["RESEND_FROM_EMAIL"] = "test@example.com"
    assert_equal true, SupporterEmailService.configured?
  end

  test "send_welcome returns false when not configured" do
    ENV["RESEND_API_KEY"] = nil
    result = SupporterEmailService.send_welcome(@supporter)
    assert_equal false, result
  end

  test "send_welcome returns false when supporter has no email" do
    ENV["RESEND_API_KEY"] = "test_key"
    ENV["RESEND_FROM_EMAIL"] = "test@example.com"
    @supporter.update!(email: nil)
    result = SupporterEmailService.send_welcome(@supporter)
    assert_equal false, result
  end

  test "send_blast returns error when not configured" do
    ENV["RESEND_API_KEY"] = nil
    result = SupporterEmailService.send_blast(
      subject: "Test",
      body_html: "Hello",
      supporters: Supporter.where(id: @supporter.id)
    )
    assert_equal 0, result[:sent]
    assert_includes result[:errors], "Email not configured"
  end

  test "personalize replaces placeholders with supporter data" do
    text = "Hello {first_name} {last_name} from {village}!"
    result = SupporterEmailService.send(:personalize, text, @supporter)
    assert_equal "Hello Maria Cruz from Test Village!", result
  end

  test "personalize escapes HTML in supporter data" do
    @supporter.update!(first_name: "<script>alert('xss')</script>")
    text = "Hello {first_name}!"
    result = SupporterEmailService.send(:personalize, text, @supporter)
    assert_includes result, "&lt;script&gt;"
    refute_includes result, "<script>"
  end

  test "preview_subject personalizes without HTML escaping" do
    text = "Hello {first_name} from {village}"
    result = SupporterEmailService.preview_subject(text, @supporter)
    assert_equal "Hello Maria from Test Village", result
  end

  test "preview_html returns full email HTML" do
    body = "Welcome {first_name}!"
    result = SupporterEmailService.preview_html(body, @supporter)
    assert_includes result, "Welcome Maria"
    assert_includes result, "<!doctype html>"
    assert_includes result, "Josh &amp; Tina for Guam"
    assert_includes result, "Campaign email update"
  end

  test "welcome_html includes supporter name" do
    html = SupporterEmailService.send(:welcome_html, @supporter)
    assert_includes html, "Maria"
    assert_includes html, "Josh &amp; Tina for Guam"
    assert_includes html, "For Governor &amp; Lt. Governor"
    assert_includes html, "Building Guam&#39;s Future Together"
    assert_includes html, "Visit official signup"
    assert_includes html, "<!doctype html>"
  end

  test "welcome_html escapes frontend url in footer and link" do
    ENV["FRONTEND_URL"] = "https://example.com/?utm_source=email&step=1"

    html = SupporterEmailService.send(:welcome_html, @supporter)

    assert_includes html, "https://example.com/?utm_source=email&amp;step=1"
    refute_includes html, "https://example.com/?utm_source=email&step=1"
  end

  test "blast_wrapper_html wraps content in template" do
    content = "<p>Campaign message here</p>"
    html = SupporterEmailService.send(:blast_wrapper_html, content)
    assert_includes html, content
    assert_includes html, "<!doctype html>"
    assert_includes html, "Josh &amp; Tina for Guam"
    assert_includes html, "Campaign email update"
  end
end
