# frozen_string_literal: true

module Api
  module V1
    class DashboardController < ApplicationController
      include Authenticatable

      OFFICIAL_UNASSIGNED_VILLAGE_NAME = "Unassigned"

      before_action :authenticate_request, only: [ :show ]

      # GET /api/v1/stats (public — no auth)
      def stats
        render json: {
          verified_supporters: Supporter.working_supporters.verified.count,
          total_supporters: Supporter.working_supporters.count,
          unverified_supporters: Supporter.working_supporters.unverified.count,
          flagged_supporters: Supporter.working_supporters.flagged.count,
          potential_duplicates: Supporter.working_supporters.potential_duplicates_only.count,
          total_villages: official_village_scope.count,
          campaign_name: Campaign.active.first&.name || CampaignBranding::CAMPAIGN_LABEL
        }
      end

      # GET /api/v1/dashboard
      def show
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
        response.headers["Pragma"] = "no-cache"

        campaign = Campaign.active.first
        Rails.logger.info("[Dashboard] user=#{current_user&.id} role=#{current_user&.role} campaign=#{campaign&.id}")

        villages_query = Village.includes(:precincts).order(:name)
        villages_base = if scoped_village_ids.nil?
          villages_query.to_a
        else
          villages_query.where(id: scoped_village_ids).to_a
        end
        village_ids = villages_base.map(&:id)

        verified_counts = Supporter.working_supporters.verified.where(village_id: village_ids).group(:village_id).count
        total_counts = Supporter.working_supporters.where(village_id: village_ids).group(:village_id).count
        unverified_counts = Supporter.working_supporters.unverified.where(village_id: village_ids).group(:village_id).count
        today_counts = Supporter.working_supporters.verified_today.where(village_id: village_ids).group(:village_id).count
        week_counts = Supporter.working_supporters.verified_this_week.where(village_id: village_ids).group(:village_id).count
        today_total_counts = Supporter.working_supporters.today.where(village_id: village_ids).group(:village_id).count
        week_total_counts = Supporter.working_supporters.this_week.where(village_id: village_ids).group(:village_id).count
        team_counts = Supporter.team_input.where(village_id: village_ids).group(:village_id).count
        public_approved_counts = Supporter.official_supporters.public_origin.where(village_id: village_ids).group(:village_id).count
        team_pending_counts = Supporter.pending_supporter_review.where(source: Supporter::TEAM_SOURCES, village_id: village_ids).group(:village_id).count
        public_counts = Supporter.active.public_signups.where(village_id: village_ids).group(:village_id).count

        villages = villages_base.map do |village|
          verified_count = verified_counts[village.id] || 0

          {
            id: village.id,
            name: village.name,
            region: village.region,
            registered_voters: village.registered_voters,
            precinct_count: village.precinct_count,
            verified_count: verified_count,
            total_count: total_counts[village.id] || 0,
            unverified_count: unverified_counts[village.id] || 0,
            supporter_count: verified_count,
            today_count: today_counts[village.id] || 0,
            today_total_count: today_total_counts[village.id] || 0,
            week_count: week_counts[village.id] || 0,
            week_total_count: week_total_counts[village.id] || 0,
            team_input_count: team_counts[village.id] || 0,
            public_approved_count: public_approved_counts[village.id] || 0,
            team_pending_count: team_pending_counts[village.id] || 0,
            public_signup_count: public_counts[village.id] || 0
          }
        end

        global_verified = Supporter.working_supporters.verified.count
        global_total = Supporter.working_supporters.count
        all_villages = Village.all
        global_total_precincts = all_villages.sum { |v| v.precinct_count.to_i }

        Rails.logger.info("[Dashboard] total_precincts=#{global_total_precincts} villages=#{villages.size}")

        render json: {
          campaign: campaign&.slice(:id, :name, :candidate_names, :election_year, :primary_color, :secondary_color),
          summary: {
            verified_supporters: global_verified,
            total_supporters: global_total,
            unverified_supporters: Supporter.working_supporters.unverified.count,
            total_registered_voters: all_villages.sum { |v| v.registered_voters.to_i },
            total_villages: official_village_scope.count,
            total_precincts: global_total_precincts,
            today_signups: Supporter.working_supporters.verified_today.count,
            today_total_signups: Supporter.working_supporters.today.count,
            week_signups: Supporter.working_supporters.verified_this_week.count,
            week_total_signups: Supporter.working_supporters.this_week.count,
            team_input_count: Supporter.team_input.count,
            public_signup_count: Supporter.active.public_signups.count
          },
          villages: villages
        }
      end

      private

      def official_village_scope
        Village.where.not(name: OFFICIAL_UNASSIGNED_VILLAGE_NAME)
      end
    end
  end
end
