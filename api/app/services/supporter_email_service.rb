# frozen_string_literal: true

class SupporterEmailService
  class << self
    # Send welcome email to a new supporter who opted in to email updates.
    def send_welcome(supporter)
      return false unless configured?
      return false if supporter.email.blank?

      body = welcome_html(supporter)
      response = Resend::Emails.send(
        {
          from: from_email,
          to: supporter.email,
          subject: CampaignBranding::WELCOME_EMAIL_SUBJECT,
          html: body
        }
      )

      Rails.logger.info("[SupporterEmail] welcome sent to #{supporter.email} response=#{response.inspect}")
      true
    rescue StandardError => e
      Rails.logger.error("[SupporterEmail] welcome failed for #{supporter.email}: #{e.class} #{e.message}")
      false
    end

    # Send a blast email to multiple supporters.
    # Returns { sent: count, failed: count, errors: [] }
    def send_blast(subject:, body_html:, supporters:)
      return { sent: 0, failed: 0, errors: [ "Email not configured" ] } unless configured?

      sent = 0
      failed = 0
      errors = []

      supporters.find_each do |supporter|
        next if supporter.email.blank?

        begin
          personalized = personalize(body_html, supporter)
          Resend::Emails.send(
            {
              from: from_email,
              to: supporter.email,
              subject: personalize(subject, supporter),
              html: blast_wrapper_html(personalized)
            }
          )
          sent += 1
        rescue StandardError => e
          failed += 1
          errors << "#{supporter.email}: #{e.message}" if errors.length < 10
          Rails.logger.error("[SupporterEmail] blast failed for #{supporter.email}: #{e.class} #{e.message}")
        end
      end

      { sent: sent, failed: failed, errors: errors }
    end

    def configured?
      if ENV["RESEND_API_KEY"].blank?
        Rails.logger.warn("[SupporterEmail] RESEND_API_KEY not configured; skipping email")
        return false
      end

      if from_email.blank?
        Rails.logger.warn("[SupporterEmail] RESEND_FROM_EMAIL missing; skipping email")
        return false
      end

      true
    end

    # Public preview methods for controller dry-run previews
    def preview_html(body, supporter)
      blast_wrapper_html(personalize(body, supporter))
    end

    def preview_subject(subject, supporter)
      subject.gsub("{first_name}", supporter.first_name.to_s)
             .gsub("{last_name}", supporter.last_name.to_s)
             .gsub("{village}", supporter.village&.name.to_s)
    end

    private

    def from_email
      ENV["RESEND_FROM_EMAIL"].presence || ENV["MAILER_FROM_EMAIL"].presence
    end

    def frontend_url
      ENV["FRONTEND_URL"].presence || "http://localhost:5175"
    end

    def escaped_frontend_url
      ERB::Util.html_escape(frontend_url)
    end

    def personalize(text, supporter)
      text.gsub("{first_name}", ERB::Util.html_escape(supporter.first_name.to_s))
          .gsub("{last_name}", ERB::Util.html_escape(supporter.last_name.to_s))
          .gsub("{village}", ERB::Util.html_escape(supporter.village&.name.to_s))
    end

    def welcome_html(supporter)
      name = ERB::Util.html_escape(supporter.first_name.presence || "Supporter")

      intro = <<~HTML
        <p style="margin: 0 0 18px 0; font-size: 16px; line-height: 1.7; color: #475569;">
          #{CampaignBranding::WELCOME_EMAIL_INTRO_HTML}
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin: 0 0 20px 0; background: #fff9ec; border: 1px solid #f0d9a4; border-radius: 18px;">
          <tr>
            <td style="padding: 16px 18px;">
              <p style="margin: 0 0 8px 0; color: #93650d; font-size: 12px; letter-spacing: 0.2em; text-transform: uppercase; font-weight: 700;">
                #{ERB::Util.html_escape(CampaignBranding::WELCOME_EMAIL_NEXT_STEP_LABEL)}
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.7; color: #475569;">
                #{ERB::Util.html_escape(CampaignBranding::WELCOME_EMAIL_NEXT_STEP_BODY)}
              </p>
            </td>
          </tr>
        </table>
        <table role="presentation" cellspacing="0" cellpadding="0" style="margin: 0 auto;">
          <tr>
            <td style="border-radius: 999px; background: #e23a22;">
              <a href="#{escaped_frontend_url}" target="_blank" style="display: inline-block; padding: 14px 28px; color: #ffffff; text-decoration: none; font-size: 15px; font-weight: 800; letter-spacing: 0.02em;">
                Visit official signup
              </a>
            </td>
          </tr>
        </table>
      HTML

      email_layout_html(
        section_label: "Official campaign supporter update",
        title: "Si Yu'os Ma'&aring;se, #{name}!",
        intro_html: intro,
        content_html: nil,
        footer_html: "You&apos;re receiving this because you signed up at #{escaped_frontend_url} and opted in to email updates.<br>If you no longer wish to receive campaign emails, please contact the campaign team."
      )
    end

    def blast_wrapper_html(content)
      email_layout_html(
        section_label: "Campaign email update",
        title: nil,
        intro_html: nil,
        content_html: content,
        footer_html: "You&apos;re receiving this because you opted in to email updates from #{ERB::Util.html_escape(CampaignBranding::CAMPAIGN_LABEL)}.<br>To unsubscribe, please contact the campaign team."
      )
    end

    def email_layout_html(section_label:, title:, intro_html:, content_html:, footer_html:)
      body_content = [ intro_html, content_html ].compact.join("\n")

      <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="color-scheme" content="light only">
            <meta name="supported-color-schemes" content="light only">
            <title>#{ERB::Util.html_escape(CampaignBranding::CAMPAIGN_LABEL)}</title>
          </head>
          <body style="margin: 0; padding: 0; background: #eef3fb; color: #0f172a; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding: 0; background: #eef3fb;">
              <tr>
                <td style="background: #0f3e86; padding: 10px 20px; text-align: center;">
                  <p style="margin: 0; color: #ffffff; font-size: 12px; letter-spacing: 0.24em; text-transform: uppercase; font-weight: 700;">#{ERB::Util.html_escape(CampaignBranding::CAMPAIGN_TAGLINE)}</p>
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
                                #{ERB::Util.html_escape(CampaignBranding::CAMPAIGN_SHORT_NAME)}
                              </p>
                              <p style="margin: 8px 0 0 0; color: #64748b; font-size: 12px; letter-spacing: 0.18em; text-transform: uppercase; font-weight: 700;">#{ERB::Util.html_escape(CampaignBranding::CAMPAIGN_SUBLABEL)}</p>
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
                      <td style="padding: 20px 24px 0 24px; background: #ffffff;">
                        <table role="presentation" cellspacing="0" cellpadding="0">
                          <tr>
                            <td style="border-radius: 999px; background: #eef4ff; border: 1px solid #d8e4f2; padding: 10px 16px;">
                              <p style="margin: 0; color: #0f3e86; font-size: 12px; letter-spacing: 0.22em; text-transform: uppercase; font-weight: 700;">
                                #{ERB::Util.html_escape(section_label)}
                              </p>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                    <tr>
                      <td style="padding: 28px 28px 30px 28px;">
                        #{title.present? ? "<h1 style=\"margin: 0 0 14px 0; color: #0f172a; font-size: 30px; line-height: 1.2; font-weight: 800; text-align: center;\">#{title}</h1>" : ""}
                        #{title.present? ? "<div style=\"width: 72px; height: 4px; margin: 0 auto 22px auto; border-radius: 999px; background: #e23a22;\"></div>" : ""}
                        <div style="font-size: 15px; line-height: 1.7; color: #334155;">
                          #{body_content}
                        </div>
                      </td>
                    </tr>
                  </table>

                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 640px;">
                    <tr>
                      <td style="padding: 18px 24px 0 24px; text-align: center;">
                        <p style="margin: 0; font-size: 11px; line-height: 1.6; color: #64748b;">
                          #{footer_html}
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
