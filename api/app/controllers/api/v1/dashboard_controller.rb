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
          # Verified = the official count
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
        all_village_ids = Village.pluck(:id)
        village_ids = villages_base.map(&:id)
        # Verified supporters are the "real" counts for quota tracking
        verified_counts = Supporter.working_supporters.verified.where(village_id: village_ids).group(:village_id).count
        # Total includes unverified — shown as secondary metric
        total_counts = Supporter.working_supporters.where(village_id: village_ids).group(:village_id).count
        unverified_counts = Supporter.working_supporters.unverified.where(village_id: village_ids).group(:village_id).count
        # "Today/Week (verified)" should reflect when a supporter was vetted.
        today_counts = Supporter.working_supporters.verified_today.where(village_id: village_ids).group(:village_id).count
        week_counts = Supporter.working_supporters.verified_this_week.where(village_id: village_ids).group(:village_id).count
        today_total_counts = Supporter.working_supporters.today.where(village_id: village_ids).group(:village_id).count
        week_total_counts = Supporter.working_supporters.this_week.where(village_id: village_ids).group(:village_id).count
        quota_targets = if campaign
          Quota.where(campaign_id: campaign.id, village_id: village_ids).group(:village_id).sum(:target_count)
        else
          {}
        end

        # Pace tracking: calculate expected progress based on linear interpolation
        # from campaign start to quota target date
        target_dates = if campaign
          Quota.where(campaign_id: campaign.id, village_id: village_ids)
               .group(:village_id)
               .maximum(:target_date)
        else
          {}
        end
        campaign_started_at = campaign&.started_at || campaign&.created_at&.to_date || Date.current

        # Pipeline/source counts per village
        team_counts = Supporter.team_input.where(village_id: village_ids).group(:village_id).count
        public_approved_counts = Supporter.official_supporters.public_origin.where(village_id: village_ids).group(:village_id).count
        team_pending_counts = Supporter.pending_supporter_review.where(source: Supporter::TEAM_SOURCES, village_id: village_ids).group(:village_id).count
        public_counts = Supporter.active.public_signups.where(village_id: village_ids).group(:village_id).count
        quota_eligible_counts = Supporter.quota_eligible.where(village_id: village_ids).group(:village_id).count

        villages = villages_base.map do |village|
          verified_count = verified_counts[village.id] || 0
          total_count = total_counts[village.id] || 0
          unverified_count = unverified_counts[village.id] || 0
          today_count = today_counts[village.id] || 0
          week_count = week_counts[village.id] || 0
          today_total_count = today_total_counts[village.id] || 0
          week_total_count = week_total_counts[village.id] || 0
          target = quota_targets[village.id] || 0
          # Quota progress based on VERIFIED supporters only
          percentage = target.positive? ? (verified_count * 100.0 / target).round(1) : 0

          # Pace calculation based on verified supporters
          pace = calculate_pace(
            supporter_count: verified_count,
            target: target,
            started_at: campaign_started_at,
            target_date: target_dates[village.id]
          )

          {
            id: village.id,
            name: village.name,
            region: village.region,
            registered_voters: village.registered_voters,
            precinct_count: village.precinct_count,
            # Verified = primary count (used for quota/pace)
            verified_count: verified_count,
            # Total = all active supporters including unverified
            total_count: total_count,
            unverified_count: unverified_count,
            # Legacy field — now points to verified for backward compat
            supporter_count: verified_count,
            today_count: today_count,
            today_total_count: today_total_count,
            week_count: week_count,
            week_total_count: week_total_count,
            quota_target: target,
            quota_percentage: percentage,
            status: percentage >= 75 ? "on_track" : percentage >= 50 ? "behind" : "critical",
            pace_expected: pace[:expected],
            pace_diff: pace[:diff],
            pace_status: pace[:status],
            pace_weekly_needed: pace[:weekly_needed],
            # Pipeline separation
            team_input_count: team_counts[village.id] || 0,
            public_approved_count: public_approved_counts[village.id] || 0,
            team_pending_count: team_pending_counts[village.id] || 0,
            public_signup_count: public_counts[village.id] || 0,
            quota_eligible_count: quota_eligible_counts[village.id] || 0
          }
        end

        # Summary cards are island-wide for all roles, even when village cards are scoped.
        global_verified = Supporter.working_supporters.verified.count
        global_total = Supporter.working_supporters.count
        global_unverified = Supporter.working_supporters.unverified.count
        global_today_verified = Supporter.working_supporters.verified_today.count
        global_week_verified = Supporter.working_supporters.verified_this_week.count
        global_today_total = Supporter.working_supporters.today.count
        global_week_total = Supporter.working_supporters.this_week.count
        global_total_target = if campaign
          Quota.where(campaign_id: campaign.id, village_id: all_village_ids).sum(:target_count)
        else
          0
        end
        # Quota percentage based on verified only
        global_team_input = Supporter.team_input.count
        global_public_signups = Supporter.active.public_signups.count
        global_quota_eligible = Supporter.quota_eligible.count
        global_total_percentage = global_total_target > 0 ? (global_verified * 100.0 / global_total_target).round(1) : 0
        all_villages = Village.all
        global_total_registered_voters = all_villages.sum { |v| v.registered_voters.to_i }
        global_total_villages = official_village_scope.count
        global_total_precincts = all_villages.sum { |v| v.precinct_count.to_i }
        global_observed_elsewhere = Supporter.working_supporters.where(turnout_status: "observed_elsewhere").count
        global_target_dates = if campaign
          Quota.where(campaign_id: campaign.id).group(:village_id).maximum(:target_date)
        else
          {}
        end

        # Overall pace based on verified supporters
        overall_pace = calculate_pace(
          supporter_count: global_verified,
          target: global_total_target,
          started_at: campaign_started_at,
          target_date: global_target_dates.values.compact.max
        )

        Rails.logger.info("[Dashboard] total_target=#{global_total_target} total_precincts=#{global_total_precincts} villages=#{villages.size}")

        render json: {
          campaign: campaign&.slice(:id, :name, :candidate_names, :election_year, :primary_color, :secondary_color)&.merge(show_pace: campaign&.show_pace || false),
          summary: {
            # Primary count: verified supporters only (counts toward quota)
            verified_supporters: global_verified,
            # Total including unverified (secondary metric)
            total_supporters: global_total,
            unverified_supporters: global_unverified,
            total_target: global_total_target,
            total_percentage: global_total_percentage,
            total_registered_voters: global_total_registered_voters,
            total_villages: global_total_villages,
            total_precincts: global_total_precincts,
            observed_elsewhere_count: global_observed_elsewhere,
            today_signups: global_today_verified,
            today_total_signups: global_today_total,
            week_signups: global_week_verified,
            week_total_signups: global_week_total,
            status: global_total_percentage >= 75 ? "on_track" : global_total_percentage >= 50 ? "behind" : "critical",
            pace_expected: overall_pace[:expected],
            pace_diff: overall_pace[:diff],
            pace_status: overall_pace[:status],
            pace_weekly_needed: overall_pace[:weekly_needed],
            # Pipeline separation
            team_input_count: global_team_input,
            public_signup_count: global_public_signups,
            quota_eligible_count: global_quota_eligible
          },
          villages: villages
        }
      end

      private

      def official_village_scope
        Village.where.not(name: OFFICIAL_UNASSIGNED_VILLAGE_NAME)
      end

      # Calculate pace metrics for a given supporter count against a target.
      # Returns expected count by now, diff (actual - expected), status, and weekly rate needed.
      def calculate_pace(supporter_count:, target:, started_at:, target_date:)
        return { expected: 0, diff: 0, status: "no_target", weekly_needed: 0 } if target <= 0
        return { expected: 0, diff: supporter_count, status: "no_deadline", weekly_needed: 0 } if target_date.blank?

        today = Date.current
        start_date = started_at || today
        total_days = (target_date - start_date).to_f
        elapsed_days = (today - start_date).to_f

        # If campaign hasn't started yet or total duration is zero/negative
        if elapsed_days <= 0 || total_days <= 0
          total_weeks = total_days > 0 ? (total_days / 7.0) : 1.0
          return { expected: 0, diff: supporter_count, status: "ahead", weekly_needed: (target / total_weeks).ceil }
        end

        # Past deadline
        if today > target_date
          return {
            expected: target,
            diff: supporter_count - target,
            status: supporter_count >= target ? "complete" : "overdue",
            weekly_needed: 0
          }
        end

        # Linear interpolation: where should we be right now?
        progress_fraction = elapsed_days / total_days
        expected = (target * progress_fraction).round

        diff = supporter_count - expected
        diff_pct = expected > 0 ? (diff.to_f / expected * 100) : 0

        # Status thresholds
        status = if diff >= 0
          "ahead"
        elsif diff_pct >= -10
          "slightly_behind"
        else
          "behind"
        end

        # How many per week needed to hit target from here?
        remaining_days = (target_date - today).to_f
        remaining_weeks = remaining_days / 7.0
        remaining_count = [ target - supporter_count, 0 ].max
        weekly_needed = remaining_weeks > 0 ? (remaining_count / remaining_weeks).ceil : remaining_count

        { expected: expected, diff: diff, status: status, weekly_needed: weekly_needed }
      end
    end
  end
end
