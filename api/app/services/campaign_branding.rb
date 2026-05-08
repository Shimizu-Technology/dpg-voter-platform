# frozen_string_literal: true

module CampaignBranding
  VARIANT = ENV.fetch("CAMPAIGN_VARIANT", "jt").to_s.downcase

  CONFIG = {
    "jt" => {
      label: "Josh & Tina for Guam",
      sublabel: "For Governor & Lt. Governor",
      tagline: "Building Guam's Future Together",
      short_name: "Josh & Tina",
      candidate_names: "Josh Tenorio & Tina Muña Barnes",
      party: "Democratic",
      welcome_sms_template: "Si Yu'os Ma'åse, {first_name}! Thank you for supporting Josh & Tina 2026. Together we'll make Guam better for everyone. #JoshAndTina2026",
      welcome_email_subject: "Si Yu'os Ma'åse for supporting Josh & Tina!",
      welcome_email_intro_html: 'Thank you for signing up to support <strong style="color: #0f172a;">Josh Tenorio &amp; Tina Mu&ntilde;a-Barnes</strong>. Your response helps the campaign understand where support is growing and how to stay connected with people across Guam.',
      welcome_email_next_step_label: "Supporter next step",
      welcome_email_next_step_body: "If you opted in for updates, the campaign may reach out with announcements, volunteer opportunities, motorcades, and other important moments."
    },
    "dpg" => {
      label: "Democratic Party of Guam",
      sublabel: "Voter Engagement Platform",
      tagline: "Democratic Party of Guam",
      short_name: "Democratic Party of Guam",
      candidate_names: "Democratic Party of Guam",
      party: "Democratic",
      welcome_sms_template: "Si Yu'os Ma'åse, {first_name}! Thank you for connecting with the Democratic Party of Guam. We'll share voter information, events, and outreach opportunities as election season moves forward.",
      welcome_email_subject: "Si Yu'os Ma'åse from the Democratic Party of Guam",
      welcome_email_intro_html: 'Thank you for signing up to stay connected with <strong style="color: #0f172a;">the Democratic Party of Guam</strong>. Your response helps the party understand voter needs, outreach opportunities, and community engagement across the island.',
      welcome_email_next_step_label: "Next step",
      welcome_email_next_step_body: "If you opted in for updates, the party may reach out with announcements, voter education, volunteer opportunities, and event information."
    }
  }.freeze

  CURRENT = CONFIG.fetch(VARIANT, CONFIG.fetch("jt"))

  CAMPAIGN_LABEL = CURRENT.fetch(:label)
  CAMPAIGN_SUBLABEL = CURRENT.fetch(:sublabel)
  CAMPAIGN_TAGLINE = CURRENT.fetch(:tagline)
  CAMPAIGN_SHORT_NAME = CURRENT.fetch(:short_name)
  CANDIDATE_NAMES = CURRENT.fetch(:candidate_names)
  PARTY = CURRENT.fetch(:party)
  DEFAULT_WELCOME_SMS_TEMPLATE = CURRENT.fetch(:welcome_sms_template)
  WELCOME_EMAIL_SUBJECT = CURRENT.fetch(:welcome_email_subject)
  WELCOME_EMAIL_INTRO_HTML = CURRENT.fetch(:welcome_email_intro_html)
  WELCOME_EMAIL_NEXT_STEP_LABEL = CURRENT.fetch(:welcome_email_next_step_label)
  WELCOME_EMAIL_NEXT_STEP_BODY = CURRENT.fetch(:welcome_email_next_step_body)
end
