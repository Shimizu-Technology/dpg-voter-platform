# frozen_string_literal: true

module Api
  module V1
    class SettingsController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_admin!

      # GET /api/v1/settings
      def show
        campaign = Campaign.active.first
        unless campaign
          return render_api_error(message: "No active campaign", status: :not_found, code: "no_campaign")
        end

        render json: settings_json(campaign)
      end

      # PATCH /api/v1/settings
      def update
        campaign = Campaign.active.first
        unless campaign
          return render_api_error(message: "No active campaign", status: :not_found, code: "no_campaign")
        end

        # SMS template
        template = params[:welcome_sms_template]
        if template.present? && template.length > 320
          return render_api_error(
            message: "Template too long (#{template.length} chars). Maximum is 320 characters (2 SMS segments).",
            status: :unprocessable_entity,
            code: "template_too_long"
          )
        end

        updates = {}
        updates[:welcome_sms_template] = template.presence if params.key?(:welcome_sms_template)
        updates[:show_pace] = ActiveModel::Type::Boolean.new.cast(params[:show_pace]) if params.key?(:show_pace)

        [ :instagram_url, :facebook_url, :tiktok_url, :twitter_url ].each do |field|
          updates[field] = params[field].presence if params.key?(field)
        end

        updates[:signup_share_prompt] = params[:signup_share_prompt].presence if params.key?(:signup_share_prompt)
        updates[:thank_you_share_prompt] = params[:thank_you_share_prompt].presence if params.key?(:thank_you_share_prompt)
        updates[:primary_election_date] = params[:primary_election_date].presence if params.key?(:primary_election_date)
        updates[:general_election_date] = params[:general_election_date].presence if params.key?(:general_election_date)

        if updates.any?
          campaign.update!(updates)
          log_audit!(campaign, action: "settings_updated", changed_data: campaign.saved_changes.except("updated_at"), normalize: true)
        end

        render json: settings_json(campaign)
      end

      private

      def settings_json(campaign)
        {
          welcome_sms_template: campaign.welcome_sms_template || SmsService::DEFAULT_WELCOME_TEMPLATE,
          welcome_sms_preview: SmsService.preview_welcome_template(campaign.welcome_sms_template),
          available_variables: SmsService::WELCOME_TEMPLATE_VARIABLES,
          show_pace: campaign.show_pace,
          instagram_url: campaign.instagram_url,
          facebook_url: campaign.facebook_url,
          tiktok_url: campaign.tiktok_url,
          twitter_url: campaign.twitter_url,
          signup_share_prompt: campaign.signup_share_prompt,
          thank_you_share_prompt: campaign.thank_you_share_prompt,
          primary_election_date: campaign.primary_election_date&.iso8601,
          general_election_date: campaign.general_election_date&.iso8601
        }
      end

      def require_admin!
        unless current_user&.admin?
          render_api_error(message: "Admin access required", status: :forbidden, code: "forbidden")
        end
      end

      def audit_entry_mode
        "settings"
      end
    end
  end
end
