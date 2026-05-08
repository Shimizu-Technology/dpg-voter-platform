# frozen_string_literal: true

class ApplyCampaignVariantDefaults < ActiveRecord::Migration[8.1]
  DPG_WELCOME_SMS = "Si Yu'os Ma'åse, {first_name}! Thank you for connecting with the Democratic Party of Guam. We'll share voter information, events, and outreach opportunities as election season moves forward."
  DPG_SIGNUP_PROMPT = "Know someone who wants to stay connected with the Democratic Party of Guam? Finish your signup, then share this form with them too."
  DPG_THANK_YOU_PROMPT = "Share this signup link with family and friends who want voter information, outreach updates, and election reminders from the Democratic Party of Guam."

  JT_WELCOME_SMS = "Si Yu'os Ma'åse, {first_name}! Thank you for supporting Josh & Tina 2026. Together we'll make Guam better for everyone. #JoshAndTina2026"

  def up
    return unless ENV.fetch("CAMPAIGN_VARIANT", "jt").to_s.downcase == "dpg"

    execute <<~SQL.squish
      UPDATE campaigns
      SET name = 'Democratic Party of Guam',
          candidate_names = 'Democratic Party of Guam',
          party = 'Democratic',
          instagram_url = NULL,
          facebook_url = NULL,
          tiktok_url = NULL,
          twitter_url = NULL,
          welcome_sms_template = #{connection.quote(DPG_WELCOME_SMS)},
          signup_share_prompt = #{connection.quote(DPG_SIGNUP_PROMPT)},
          thank_you_share_prompt = #{connection.quote(DPG_THANK_YOU_PROMPT)},
          updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active'
    SQL
  end

  def down
    return unless ENV.fetch("CAMPAIGN_VARIANT", "jt").to_s.downcase == "dpg"

    execute <<~SQL.squish
      UPDATE campaigns
      SET name = 'Josh & Tina for Guam',
          candidate_names = 'Josh Tenorio & Tina Muña Barnes',
          party = 'Democratic',
          welcome_sms_template = #{connection.quote(JT_WELCOME_SMS)},
          updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active'
    SQL
  end
end
