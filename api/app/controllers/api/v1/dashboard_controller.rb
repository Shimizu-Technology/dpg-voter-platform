# frozen_string_literal: true

module Api
  module V1
    class DashboardController < ApplicationController
      include Authenticatable

      OFFICIAL_UNASSIGNED_VILLAGE_NAME = "Unassigned"

      before_action :authenticate_request, only: [ :show ]

      # GET /api/v1/stats (public — no auth)
      def stats
        contacts = Supporter.contacts
        total_contacts = contacts.count
        matched_contacts = contacts.verified.count

        render json: {
          verified_supporters: matched_contacts,
          total_supporters: total_contacts,
          unverified_supporters: contacts.unverified.count,
          flagged_supporters: contacts.flagged.count,
          potential_duplicates: contacts.potential_duplicates_only.count,
          total_contacts: total_contacts,
          new_intake: Supporter.intake.count,
          matched_to_gec: matched_contacts,
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

        contacts_scope = Supporter.contacts
        verified_counts = contacts_scope.verified.where(village_id: village_ids).group(:village_id).count
        total_counts = contacts_scope.where(village_id: village_ids).group(:village_id).count
        intake_counts = Supporter.intake.where(village_id: village_ids).group(:village_id).count
        supporter_counts = Supporter.classified_supporters.where(village_id: village_ids).group(:village_id).count
        member_counts = Supporter.members.where(village_id: village_ids).group(:village_id).count
        volunteer_counts = Supporter.volunteers.where(village_id: village_ids).group(:village_id).count
        follow_up_counts = contacts_scope.needs_follow_up.where(village_id: village_ids).group(:village_id).count
        unverified_counts = contacts_scope.unverified.where(village_id: village_ids).group(:village_id).count
        today_counts = contacts_scope.verified_today.where(village_id: village_ids).group(:village_id).count
        week_counts = contacts_scope.verified_this_week.where(village_id: village_ids).group(:village_id).count
        today_total_counts = contacts_scope.today.where(village_id: village_ids).group(:village_id).count
        week_total_counts = contacts_scope.this_week.where(village_id: village_ids).group(:village_id).count
        team_counts = contacts_scope.where(source: Supporter::TEAM_SOURCES).where(village_id: village_ids).group(:village_id).count
        public_counts = contacts_scope.public_origin.where(village_id: village_ids).group(:village_id).count

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
            total_contacts: total_counts[village.id] || 0,
            new_intake_count: intake_counts[village.id] || 0,
            supporter_count: supporter_counts[village.id] || 0,
            member_count: member_counts[village.id] || 0,
            volunteer_count: volunteer_counts[village.id] || 0,
            needs_follow_up_count: follow_up_counts[village.id] || 0,
            matched_to_gec_count: verified_count,
            unverified_count: unverified_counts[village.id] || 0,
            today_count: today_counts[village.id] || 0,
            today_total_count: today_total_counts[village.id] || 0,
            week_count: week_counts[village.id] || 0,
            week_total_count: week_total_counts[village.id] || 0,
            team_input_count: team_counts[village.id] || 0,
            public_approved_count: public_counts[village.id] || 0,
            team_pending_count: intake_counts[village.id] || 0,
            public_signup_count: public_counts[village.id] || 0
          }
        end

        global_contacts = Supporter.contacts
        global_verified = global_contacts.verified.count
        global_total = global_contacts.count
        global_intake = Supporter.intake.count
        global_supporters = Supporter.classified_supporters.count
        global_members = Supporter.members.count
        global_volunteers = Supporter.volunteers.count
        global_follow_up = global_contacts.needs_follow_up.count
        global_unverified = global_contacts.unverified.count
        global_today_verified = global_contacts.verified_today.count
        global_today_total = global_contacts.today.count
        global_week_verified = global_contacts.verified_this_week.count
        global_week_total = global_contacts.this_week.count
        global_team_input = global_contacts.where(source: Supporter::TEAM_SOURCES).count
        global_public_signups = global_contacts.public_origin.count
        all_villages = Village.all
        global_total_precincts = all_villages.sum { |v| v.precinct_count.to_i }

        active_quota_period = QuotaPeriod.active_for

        Rails.logger.info("[Dashboard] total_precincts=#{global_total_precincts} villages=#{villages.size}")

        render json: {
          campaign: campaign&.slice(:id, :name, :candidate_names, :election_year, :primary_color, :secondary_color),
          active_quota_period: active_quota_period && quota_period_dashboard_json(active_quota_period),
          summary: {
            total_contacts: global_total,
            new_intake: global_intake,
            supporters: global_supporters,
            members: global_members,
            volunteers: global_volunteers,
            needs_follow_up: global_follow_up,
            matched_to_gec: global_verified,
            verified_supporters: global_verified,
            total_supporters: global_total,
            unverified_supporters: global_unverified,
            total_registered_voters: all_villages.sum { |v| v.registered_voters.to_i },
            total_villages: official_village_scope.count,
            total_precincts: global_total_precincts,
            today_signups: global_today_verified,
            today_total_signups: global_today_total,
            week_signups: global_week_verified,
            week_total_signups: global_week_total,
            team_input_count: global_team_input,
            public_signup_count: global_public_signups
          },
          villages: villages
        }
      end

      private

      def quota_period_dashboard_json(period)
        scope = Supporter.active.where(quota_period_id: period.id)
        classification_counts = scope.group(:contact_classification).count
        source_counts = scope.group(:source).count
        supporter_count = scope.where(contact_classification: "active_contact", support_status: "supporter").count
        excluded_contact_classifications = %w[archived invalid duplicate]

        {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date,
          due_date: period.due_date,
          quota_target: period.quota_target,
          status: period.status,
          counts: {
            total_contacts: classification_counts.excluding(*excluded_contact_classifications).values.sum,
            pending_intake: classification_counts["new_intake"] || 0,
            active_contacts: classification_counts["active_contact"] || 0,
            supporters: supporter_count,
            qr_signups: source_counts["qr_signup"] || 0,
            public_signups: source_counts["public_signup"] || 0
          }
        }
      end

      def official_village_scope
        Village.where.not(name: OFFICIAL_UNASSIGNED_VILLAGE_NAME)
      end
    end
  end
end
