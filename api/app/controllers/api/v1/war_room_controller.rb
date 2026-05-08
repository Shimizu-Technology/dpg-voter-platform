# frozen_string_literal: true

module Api
  module V1
    class WarRoomController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_war_room_access!

      # GET /api/v1/war_room
      def index
        precinct_scope = accessible_precinct_scope
        precinct_rows = precinct_scope.select(:id, :village_id, :registered_voters)
        accessible_precinct_ids = precinct_rows.map(&:id)
        accessible_village_ids = precinct_rows.map(&:village_id).compact.uniq

        village_scope = Village.where(id: accessible_village_ids)
        supporter_scope = accessible_supporter_scope(accessible_precinct_ids)
        working_supporter_scope = Supporter.working_supporters.merge(supporter_scope)
        linked_supporter_scope = working_supporter_scope.where.not(gec_voter_id: nil)
        election_day_voters = GecVoter.election_day_active.where(precinct_id: accessible_precinct_ids)

        latest_reports = PollReport.today
          .latest_per_precinct
          .where(precinct_id: accessible_precinct_ids)
          .index_by(&:precinct_id)
        all_reports_today = PollReport.today
          .where(precinct_id: accessible_precinct_ids)
          .chronological
          .includes(precinct: :village)
          .limit(20)

        precinct_ids_by_village = Hash.new { |hash, key| hash[key] = [] }
        registered_voters_by_village = Hash.new(0)
        precinct_rows.each do |precinct|
          precinct_ids_by_village[precinct.village_id] << precinct.id
          registered_voters_by_village[precinct.village_id] += precinct.registered_voters.to_i
        end

        supporter_counts_by_village = supporter_scope.group(:village_id).count
        motorcade_counts_by_village = supporter_scope.where(motorcade_available: true).group(:village_id).count
        not_yet_voted_counts_by_village = linked_supporter_scope
          .joins(:gec_voter)
          .merge(GecVoter.election_day_active.where(precinct_id: accessible_precinct_ids).not_yet_voted)
          .group(:village_id)
          .distinct
          .count(:id)
        observed_elsewhere_counts_by_village = linked_supporter_scope
          .joins(:gec_voter)
          .merge(GecVoter.election_day_active.observed_elsewhere)
          .group(:village_id)
          .distinct
          .count(:id)
        outreach_attempted_counts_by_village = SupporterContactAttempt
          .joins(:supporter)
          .merge(linked_supporter_scope)
          .where(outcome: "attempted")
          .group("supporters.village_id")
          .distinct
          .count(:supporter_id)
        outreach_reached_counts_by_village = SupporterContactAttempt
          .joins(:supporter)
          .merge(linked_supporter_scope)
          .where(outcome: "reached")
          .group("supporters.village_id")
          .distinct
          .count(:supporter_id)
        not_yet_voted_supporters = not_yet_voted_supporter_queue(linked_supporter_scope, accessible_precinct_ids)
        observed_elsewhere_supporters = observed_elsewhere_supporter_queue(linked_supporter_scope)
        unmatched_supporters = unmatched_supporter_queue(working_supporter_scope, accessible_village_ids)

        # Village-level aggregation
        villages = village_scope.order(:name).map do |village|
          precinct_ids = precinct_ids_by_village[village.id]
          village_reports = latest_reports.values_at(*precinct_ids).compact
          total_registered = registered_voters_by_village[village.id]
          total_voted = village_reports.sum(&:voter_count)
          reporting_count = village_reports.size

          # Supporters who haven't been contacted / need calls
          supporter_count = supporter_counts_by_village[village.id] || 0
          motorcade_count = motorcade_counts_by_village[village.id] || 0
          not_yet_voted_count = not_yet_voted_counts_by_village[village.id] || 0
          observed_elsewhere_count = observed_elsewhere_counts_by_village[village.id] || 0
          outreach_attempted_count = outreach_attempted_counts_by_village[village.id] || 0
          outreach_reached_count = outreach_reached_counts_by_village[village.id] || 0

          {
            id: village.id,
            name: village.name,
            region: village.region,
            total_precincts: precinct_ids.size,
            reporting_precincts: reporting_count,
            registered_voters: total_registered,
            voters_reported: total_voted,
            turnout_pct: total_registered > 0 ? (total_voted * 100.0 / total_registered).round(1) : 0,
            supporter_count: supporter_count,
            motorcade_count: motorcade_count,
            not_yet_voted_count: not_yet_voted_count,
            observed_elsewhere_count: observed_elsewhere_count,
            outreach_attempted_count: outreach_attempted_count,
            outreach_reached_count: outreach_reached_count,
            status: reporting_count == 0 ? "no_data" :
                    (total_voted * 100.0 / [ total_registered, 1 ].max) >= 50 ? "strong" :
                    (total_voted * 100.0 / [ total_registered, 1 ].max) >= 30 ? "moderate" : "low",
            has_issues: village_reports.any? { |r| r.report_type == "issue" }
          }
        end

        # Island-wide stats
        total_precincts = precinct_rows.size
        reporting = latest_reports.size
        total_voted = latest_reports.values.sum(&:voter_count)
        total_registered = registered_voters_by_village.values.sum
        total_unmatched_supporters = working_supporter_scope.where(gec_voter_id: nil).count

        # Time-based activity
        last_hour_reports = PollReport
          .where(precinct_id: accessible_precinct_ids)
          .where("reported_at >= ?", 1.hour.ago)
          .count

        # Call bank priorities — villages with low turnout but many supporters
        call_priorities = villages
          .select { |v| v[:reporting_precincts] > 0 && v[:turnout_pct] < 40 && v[:supporter_count] > 20 }
          .sort_by { |v| v[:turnout_pct] }
          .first(5)

        not_yet_voted_queue = villages
          .select { |v| v[:not_yet_voted_count].positive? }
          .sort_by { |v| [ -v[:not_yet_voted_count], v[:turnout_pct] ] }
          .first(8)
          .map do |v|
            {
              id: v[:id],
              name: v[:name],
              turnout_pct: v[:turnout_pct],
              not_yet_voted_count: v[:not_yet_voted_count],
              outreach_attempted_count: v[:outreach_attempted_count],
              outreach_reached_count: v[:outreach_reached_count]
            }
          end

        # Recent activity feed
        activity = all_reports_today.map do |r|
          {
            id: r.id,
            precinct_number: r.precinct.number,
            village_name: r.precinct.village.name,
            voter_count: r.voter_count,
            report_type: r.report_type,
            notes: r.notes,
            reported_at: r.reported_at.iso8601
          }
        end

        render json: {
          election_day: election_day_payload,
          villages: villages,
          stats: {
            total_precincts: total_precincts,
            reporting_precincts: reporting,
            reporting_pct: total_precincts > 0 ? (reporting * 100.0 / total_precincts).round(1) : 0,
            total_voted: total_voted,
            total_registered: total_registered,
            island_turnout_pct: total_registered > 0 ? (total_voted * 100.0 / total_registered).round(1) : 0,
            last_hour_reports: last_hour_reports,
            total_supporters: supporter_counts_by_village.values.sum,
            total_not_yet_voted: not_yet_voted_counts_by_village.values.sum,
            total_observed_elsewhere: observed_elsewhere_counts_by_village.values.sum,
            total_outreach_attempted: outreach_attempted_counts_by_village.values.sum,
            total_outreach_reached: outreach_reached_counts_by_village.values.sum,
            total_unmatched_supporters: total_unmatched_supporters,
            election_day_voters: election_day_voters.count
          },
          call_priorities: call_priorities,
          not_yet_voted_queue: not_yet_voted_queue,
          not_yet_voted_supporters: not_yet_voted_supporters,
          observed_elsewhere_supporters: observed_elsewhere_supporters,
          unmatched_supporters: unmatched_supporters,
          activity: activity
        }
      end

      # POST /api/v1/war_room/supporters/:supporter_id/contact_attempts
      def create_contact_attempt
        supporter = find_accessible_supporter!(params[:supporter_id])
        return unless supporter

        attempt = supporter.supporter_contact_attempts.new(
          outcome: contact_attempt_params[:outcome],
          channel: contact_attempt_params[:channel],
          note: contact_attempt_params[:note],
          recorded_at: Time.current,
          recorded_by_user: current_user
        )

        if attempt.save
          log_contact_attempt_audit!(attempt, supporter: supporter)
          render json: {
            message: "Contact attempt logged",
            contact_attempt: {
              id: attempt.id,
              supporter_id: supporter.id,
              outcome: attempt.outcome,
              channel: attempt.channel,
              note: attempt.note,
              recorded_at: attempt.recorded_at.iso8601
            }
          }, status: :created
        else
          render json: { errors: attempt.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def contact_attempt_params
        params.require(:contact_attempt).permit(:outcome, :channel, :note)
      end

      def accessible_supporter_scope(accessible_precinct_ids)
        return Supporter.none if accessible_precinct_ids.blank?

        Supporter
          .active
          .left_outer_joins(:gec_voter)
          .where(
            "supporters.precinct_id IN (:precinct_ids) OR gec_voters.precinct_id IN (:precinct_ids)",
            precinct_ids: accessible_precinct_ids
          )
          .distinct
      end

      def find_accessible_supporter!(supporter_id)
        supporter = accessible_supporter_scope(accessible_precinct_scope.select(:id)).find_by(id: supporter_id)
        if supporter.nil?
          render_api_error(
            message: "Supporter not found in accessible war room scope",
            status: :not_found,
            code: "supporter_not_found"
          )
          return nil
        end

        supporter
      end

      def accessible_precinct_scope
        scope = Precinct.all

        if current_user.admin?
          scope
        elsif current_user.coordinator?
          current_user.assigned_district_id.present? ? scope.joins(:village).where(villages: { district_id: current_user.assigned_district_id }) : scope
        elsif current_user.chief?
          current_user.assigned_village_id.present? ? scope.where(village_id: current_user.assigned_village_id) : scope.none
        else
          scope.none
        end
      end

      def not_yet_voted_supporter_queue(linked_supporter_scope, accessible_precinct_ids)
        linked_supporter_scope
          .joins(:gec_voter)
          .merge(GecVoter.election_day_active.where(precinct_id: accessible_precinct_ids).not_yet_voted)
          .includes(:village, :precinct, :supporter_contact_attempts, gec_voter: :turnout_updated_by_user)
          .order(:last_name, :first_name, :id)
          .limit(50)
          .map { |supporter| supporter_queue_payload(supporter) }
      end

      def unmatched_supporter_queue(working_supporter_scope, accessible_village_ids)
        working_supporter_scope
          .where(gec_voter_id: nil, village_id: accessible_village_ids)
          .includes(:village, :precinct)
          .order(:village_id, :last_name, :first_name, :id)
          .limit(25)
          .map do |supporter|
            {
              id: supporter.id,
              print_name: supporter.print_name,
              contact_number: supporter.contact_number,
              village_id: supporter.village_id,
              village_name: supporter.village&.name,
              precinct_id: supporter.precinct_id,
              precinct_number: supporter.precinct&.number,
              verification_status: supporter.verification_status,
              verification_reason: supporter.verification_reason
            }
          end
      end

      def observed_elsewhere_supporter_queue(linked_supporter_scope)
        linked_supporter_scope
          .joins(:gec_voter)
          .merge(GecVoter.election_day_active.observed_elsewhere)
          .includes(:village, :precinct, :supporter_contact_attempts, gec_voter: :turnout_updated_by_user)
          .order(:last_name, :first_name, :id)
          .limit(25)
          .map { |supporter| supporter_queue_payload(supporter) }
      end

      def supporter_queue_payload(supporter)
        latest_attempt = supporter.supporter_contact_attempts.max_by(&:recorded_at)
        {
          id: supporter.id,
          print_name: supporter.print_name,
          contact_number: supporter.contact_number,
          village_id: supporter.village_id,
          village_name: supporter.village&.name,
          precinct_id: supporter.precinct_id || supporter.gec_voter&.precinct_id,
          precinct_number: supporter.precinct&.number || supporter.gec_voter&.precinct_number,
          gec_village_name: supporter.gec_voter&.village_name,
          gec_voter_id: supporter.gec_voter_id,
          turnout_status: supporter.gec_voter&.turnout_status,
          turnout_note: supporter.gec_voter&.turnout_note,
          turnout_updated_at: supporter.gec_voter&.turnout_updated_at&.iso8601,
          turnout_updated_by_user_name: supporter.gec_voter&.turnout_updated_by_user&.name,
          latest_contact_attempt: latest_attempt && {
            outcome: latest_attempt.outcome,
            channel: latest_attempt.channel,
            recorded_at: latest_attempt.recorded_at.iso8601
          }
        }
      end

      def log_contact_attempt_audit!(attempt, supporter:)
        AuditLog.create!(
          auditable: attempt,
          actor_user: current_user,
          action: "created",
          changed_data: normalized_changed_data(
            outcome: [ nil, attempt.outcome ],
            channel: [ nil, attempt.channel ],
            note: [ nil, attempt.note ],
            recorded_at: [ nil, attempt.recorded_at ],
            supporter_id: [ nil, supporter.id ]
          ),
          metadata: {
            resource: "supporter_contact_attempt",
            precinct_id: supporter.gec_voter&.precinct_id || supporter.precinct_id,
            compliance_context: "campaign_operations_not_official_record"
          }
        )
      end

      def normalized_changed_data(changed_data)
        changed_data.each_with_object({}) do |(field, value), output|
          if value.is_a?(Array) && value.length == 2
            output[field] = { from: value[0], to: value[1] }
          else
            output[field] = { from: nil, to: value }
          end
        end
      end

      def election_day_payload
        active_import = GecImport.active_election_day_import
        {
          list_date: GecVoter.election_day_list_date&.iso8601,
          active_import_id: active_import&.id,
          active_import_filename: active_import&.filename,
          active_import_set_at: active_import&.activated_for_election_at&.iso8601,
          active_import_explicit: active_import.present?
        }
      end
    end
  end
end
