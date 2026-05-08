# frozen_string_literal: true

# High-level SMS messaging for the DPG voter engagement platform.
class SmsService
  CAMPAIGN_NAME = CampaignBranding::CAMPAIGN_LABEL

  DEFAULT_WELCOME_TEMPLATE = CampaignBranding::DEFAULT_WELCOME_SMS_TEMPLATE

  WELCOME_TEMPLATE_VARIABLES = %w[first_name last_name village].freeze

  class << self
    # ── Supporter signup confirmation ──────────────────────────────
    def welcome_supporter_body(supporter)
      template = Campaign.active.first&.welcome_sms_template.presence || DEFAULT_WELCOME_TEMPLATE
      render_template(template, supporter)
    end

    def preview_welcome_template(template = nil)
      template = template.presence || DEFAULT_WELCOME_TEMPLATE
      template
        .gsub("{first_name}", "Maria")
        .gsub("{last_name}", "Cruz")
        .gsub("{village}", "Tamuning")
    end

    def welcome_supporter(supporter)
      send(to: supporter.contact_number, body: welcome_supporter_body(supporter), category: "welcome")
    end

    # ── Custom blast to a list of supporters ───────────────────────
    def blast(supporters, message)
      results = { sent: 0, failed: 0, skipped: 0 }

      supporters.find_each do |supporter|
        phone = supporter.contact_number
        if phone.blank?
          results[:skipped] += 1
          next
        end

        result = send(to: phone, body: message, category: "blast")
        result[:success] ? results[:sent] += 1 : results[:failed] += 1

        # Be nice to the API — small delay between messages
        sleep(0.1)
      end

      results
    end

    # ── Account info ───────────────────────────────────────────────
    def balance
      ClicksendClient.account_balance
    end

    private

    def render_template(template, supporter)
      template
        .gsub("{first_name}", supporter.first_name.presence || supporter.print_name.to_s)
        .gsub("{last_name}", supporter.last_name.to_s)
        .gsub("{village}", supporter.village&.name.to_s)
    end

    def send(to:, body:, category: "general")
      if to.blank?
        Rails.logger.warn("[SmsService] Skipping SMS (#{category}) — no phone number")
        return { success: false, error: "no_phone" }
      end

      # Log for tracking
      Rails.logger.info("[SmsService] #{category}: sending to #{to}")

      ClicksendClient.send_sms(to: to, body: body)
    end
  end
end
