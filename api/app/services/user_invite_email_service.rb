# frozen_string_literal: true

require "cgi"

class UserInviteEmailService
  class << self
    def send_invite(user:, invited_by:)
      return false unless configured?

      response = Resend::Emails.send(
        {
          from: from_email,
          to: user.email,
          subject: "You’re invited to the #{CampaignBranding::CAMPAIGN_SHORT_NAME} staff workspace",
          html: invite_html(user: user, invited_by: invited_by)
        }
      )

      Rails.logger.info("[InviteEmail] sent invite to #{user.email} response=#{response.inspect}")
      true
    rescue StandardError => e
      Rails.logger.error("[InviteEmail] failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    def configured?
      if ENV["RESEND_API_KEY"].blank?
        Rails.logger.warn("[InviteEmail] RESEND_API_KEY not configured; skipping invite email")
        return false
      end

      if from_email.blank?
        Rails.logger.warn("[InviteEmail] RESEND_FROM_EMAIL/MAILER_FROM_EMAIL missing; skipping invite email")
        return false
      end

      true
    end

    private

    def from_email
      ENV["RESEND_FROM_EMAIL"].presence || ENV["MAILER_FROM_EMAIL"].presence
    end

    def frontend_url
      ENV["FRONTEND_URL"].presence || "http://localhost:5175"
    end

    def escaped_frontend_url
      escape_html(frontend_url)
    end

    def role_label(role)
      role.to_s.tr("_", " ")
    end

    def assignment_context_html(user)
      if user.assigned_district_id.present?
        district_name = District.find_by(id: user.assigned_district_id)&.name.presence || "District ##{user.assigned_district_id}"
        return "<p style=\"margin: 0 0 14px 0; font-size: 14px; line-height: 1.7; color: #475569;\"><strong style=\"color: #0f172a;\">Assigned district:</strong> #{escape_html(district_name)}</p>"
      end

      if user.assigned_village_id.present?
        village_name = Village.find_by(id: user.assigned_village_id)&.name.presence || "Village ##{user.assigned_village_id}"
        return "<p style=\"margin: 0 0 14px 0; font-size: 14px; line-height: 1.7; color: #475569;\"><strong style=\"color: #0f172a;\">Assigned village:</strong> #{escape_html(village_name)}</p>"
      end

      ""
    end

    def escape_html(value)
      CGI.escapeHTML(value.to_s)
    end

    def invite_html(user:, invited_by:)
      inviter = escape_html(invited_by&.name.presence || invited_by&.email.presence || "a party admin")
      role = escape_html(role_label(user.role).split.map(&:capitalize).join(" "))
      assignment_context = assignment_context_html(user)

      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="color-scheme" content="light only">
            <meta name="supported-color-schemes" content="light only">
            <title>#{escape_html(CampaignBranding::CAMPAIGN_LABEL)} Staff Invite</title>
          </head>
          <body style="margin: 0; padding: 0; background: #eef3fb; color: #0f172a; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding: 0; background: #eef3fb;">
              <tr>
                <td style="background: #0f3e86; padding: 10px 20px; text-align: center;">
                  <p style="margin: 0; color: #ffffff; font-size: 12px; letter-spacing: 0.24em; text-transform: uppercase; font-weight: 700;">#{escape_html(CampaignBranding::CAMPAIGN_TAGLINE)}</p>
                </td>
              </tr>
            </table>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding: 16px 12px 24px 12px; background: #eef3fb;">
              <tr>
                <td align="center">
                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 640px;">
                    <tr>
                      <td style="padding: 0 8px 10px 8px;">
                        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background: #f8fbff; border: 1px solid #d8e4f2; border-radius: 20px;">
                          <tr>
                            <td style="padding: 16px 22px; text-align: center;">
                              <p style="margin: 0; color: #0f3e86; font-size: 34px; line-height: 1; font-style: italic; font-weight: 900; letter-spacing: -0.08em;">
                                #{escape_html(CampaignBranding::CAMPAIGN_SHORT_NAME)}
                              </p>
                              <p style="margin: 8px 0 0 0; color: #64748b; font-size: 12px; letter-spacing: 0.18em; text-transform: uppercase; font-weight: 700;">#{escape_html(CampaignBranding::CAMPAIGN_SUBLABEL)}</p>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                  </table>
                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 640px; background: #ffffff; border: 1px solid #d8e4f2; border-radius: 24px; overflow: hidden; box-shadow: 0 18px 40px rgba(15, 62, 134, 0.08);">
                    <tr>
                      <td style="height: 8px; background: #d5a332; font-size: 0; line-height: 0;">&nbsp;</td>
                    </tr>
                    <tr>
                      <td style="padding: 20px 24px 0 24px;">
                        <table role="presentation" cellspacing="0" cellpadding="0">
                          <tr>
                            <td style="border-radius: 999px; background: #eef4ff; border: 1px solid #d8e4f2; padding: 10px 16px;">
                              <p style="margin: 0; color: #0f3e86; font-size: 12px; letter-spacing: 0.22em; text-transform: uppercase; font-weight: 700;">
                                Staff workspace invitation
                              </p>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding: 28px 28px 30px 28px;">
                        <h1 style="margin: 0 0 14px 0; color: #0f172a; font-size: 30px; line-height: 1.2; font-weight: 800; text-align: center;">
                          You&apos;re invited to the staff workspace
                        </h1>
                        <div style="width: 72px; height: 4px; margin: 0 auto 22px auto; border-radius: 999px; background: #e23a22;"></div>
                        <p style="margin: 0 0 16px 0; font-size: 16px; line-height: 1.7; color: #475569;">
                          #{inviter} added you as <strong style="color: #0f172a;">#{role}</strong> for #{escape_html(CampaignBranding::CAMPAIGN_LABEL)}.
                        </p>
                        #{assignment_context}
                        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin: 0 0 20px 0; background: #fff9ec; border: 1px solid #f0d9a4; border-radius: 18px;">
                          <tr>
                            <td style="padding: 16px 18px;">
                              <p style="margin: 0 0 8px 0; color: #93650d; font-size: 12px; letter-spacing: 0.2em; text-transform: uppercase; font-weight: 700;">
                                Sign-in note
                              </p>
                              <p style="margin: 0; font-size: 15px; line-height: 1.7; color: #475569;">
                                Create your account using this invited email address: <strong style="color: #0f172a;">#{escape_html(user.email)}</strong>.
                                After opening the portal, choose <strong style="color: #0f172a;">Sign up</strong> if this is your first time.
                              </p>
                            </td>
                          </tr>
                        </table>
                        <table role="presentation" cellspacing="0" cellpadding="0" style="margin: 0 auto 18px auto;">
                          <tr>
                            <td style="border-radius: 999px; background: #e23a22;">
                              <a href="#{escaped_frontend_url}/staff" target="_blank" style="display: inline-block; padding: 14px 28px; color: #ffffff; text-decoration: none; font-size: 15px; font-weight: 800; letter-spacing: 0.02em;">
                                Open staff workspace
                              </a>
                            </td>
                          </tr>
                        </table>
                        <p style="margin: 0 0 8px 0; font-size: 13px; color: #64748b;">
                          Or copy this URL into your browser:
                        </p>
                        <p style="margin: 0 0 20px 0; font-size: 13px; color: #0f3e86; word-break: break-all;">
                          #{escaped_frontend_url}/staff
                        </p>
                        <p style="margin: 0; font-size: 12px; line-height: 1.6; color: #64748b;">
                          If you already created your account, you can sign in normally.<br>
                          If you were not expecting this invite, you can ignore this email.
                        </p>
                      </td>
                    </tr>
                  </table>
                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 640px;">
                    <tr>
                      <td style="padding: 18px 24px 0 24px; text-align: center;">
                        <p style="margin: 0; font-size: 11px; line-height: 1.6; color: #64748b;">
                          This invitation is for internal party use only. Contact the party admin if you need help accessing the staff workspace.
                        </p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    end
  end
end
