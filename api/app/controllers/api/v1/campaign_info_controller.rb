# frozen_string_literal: true

module Api
  module V1
    class CampaignInfoController < ApplicationController
      # No authentication required — public info
      def show
        campaign = Campaign.active.first
        unless campaign
          return render_api_error(message: "No active campaign", status: :not_found, code: "no_campaign")
        end

        render json: {
          name: campaign.name,
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
    end
  end
end
