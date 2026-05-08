require "test_helper"

class UserInviteEmailServiceTest < ActiveSupport::TestCase
  def setup
    @village = Village.create!(name: "Barrigada")
    @user = User.create!(
      clerk_id: "clerk_invited_#{SecureRandom.hex(4)}",
      email: "staff@example.com",
      name: "Staff User",
      role: "data_team",
      assigned_village_id: @village.id
    )
    @invited_by = User.create!(
      clerk_id: "clerk_admin_#{SecureRandom.hex(4)}",
      email: "admin@example.com",
      name: "Campaign Admin",
      role: "campaign_admin"
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

    assert_equal false, UserInviteEmailService.configured?
  end

  test "configured? returns true when env vars are present" do
    ENV["RESEND_API_KEY"] = "test_key"
    ENV["RESEND_FROM_EMAIL"] = "test@example.com"

    assert_equal true, UserInviteEmailService.configured?
  end

  test "send_invite returns false when not configured" do
    ENV["RESEND_API_KEY"] = nil

    result = UserInviteEmailService.send_invite(user: @user, invited_by: @invited_by)

    assert_equal false, result
  end

  test "invite_html includes brand styling and assignment context" do
    html = UserInviteEmailService.send(:invite_html, user: @user, invited_by: @invited_by)

    assert_includes html, "Josh &amp; Tina for Guam"
    assert_includes html, "For Governor &amp; Lt. Governor"
    assert_includes html, "Staff workspace invitation"
    assert_includes html, "Building Guam&#39;s Future Together"
    assert_includes html, "Campaign Admin"
    assert_includes html, "Data Team"
    assert_includes html, "Assigned village:"
    assert_includes html, "Barrigada"
    assert_includes html, "Open staff workspace"
    assert_includes html, "/staff"
  end

  test "invite_html escapes frontend url in href and fallback text" do
    ENV["FRONTEND_URL"] = "https://example.com/?utm_source=email&step=1"

    html = UserInviteEmailService.send(:invite_html, user: @user, invited_by: @invited_by)

    assert_includes html, "https://example.com/?utm_source=email&amp;step=1/staff"
    refute_includes html, "https://example.com/?utm_source=email&step=1/staff"
  end
end
