# frozen_string_literal: true

module Api
  module V1
    class PollWatcherController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_poll_watcher_access!

      # GET /api/v1/poll_watcher
      # Returns all precincts grouped by village with latest report data
      def index
        accessible_precincts = precinct_scope_for_current_user.includes(:village).order(:number)
        latest_reports = if active_election_event
          PollReport.for_election(active_election_event)
            .latest_per_precinct
            .where(precinct_id: accessible_precincts.select(:id))
            .index_by(&:precinct_id)
        else
          {}
        end

        villages = accessible_precincts.group_by(&:village).sort_by { |village, _| village.name }.map do |village, village_precincts|
          precincts = village_precincts.map do |p|
            report = latest_reports[p.id]
            {
              id: p.id,
              number: p.number,
              polling_site: p.polling_site,
              registered_voters: p.registered_voters,
              alpha_range: p.alpha_range,
              last_voter_count: report&.voter_count,
              last_report_type: report&.report_type,
              last_report_at: report&.reported_at&.iso8601,
              last_notes: report&.notes,
              turnout_pct: report && p.registered_voters&.positive? ?
                (report.voter_count * 100.0 / p.registered_voters).round(1) : nil,
              reporting: report.present?
            }
          end

          {
            id: village.id,
            name: village.name,
            precincts: precincts,
            reporting_count: precincts.count { |p| p[:reporting] },
            total_precincts: precincts.size
          }
        end

        # Island-wide stats
        total_precincts = accessible_precincts.size
        reporting = latest_reports.size
        total_voters_reported = latest_reports.values.sum(&:voter_count)
        total_registered = accessible_precincts.sum { |p| p.registered_voters || 0 }

        render json: {
          election_day: election_day_payload,
          villages: villages,
          stats: {
            total_precincts: total_precincts,
            reporting_precincts: reporting,
            reporting_pct: total_precincts > 0 ? (reporting * 100.0 / total_precincts).round(1) : 0,
            total_voters_reported: total_voters_reported,
            total_registered_reporting: total_registered,
            overall_turnout_pct: total_registered > 0 ? (total_voters_reported * 100.0 / total_registered).round(1) : 0
          }
        }
      end

      # POST /api/v1/poll_watcher/report
      def report
        unless active_election_event
          return render_api_error(
            message: "A training or live election must be current before poll reports can be submitted",
            status: :unprocessable_entity,
            code: "current_election_required"
          )
        end

        precinct = precinct_scope_for_current_user.find_by(id: report_params[:precinct_id])
        unless precinct
          return render_api_error(
            message: "Not authorized for this precinct",
            status: :forbidden,
            code: "precinct_not_authorized"
          )
        end

        report = PollReport.new(report_params)
        report.precinct = precinct
        report.user = current_user
        report.election_event = active_election_event
        report.reported_at = Time.current

        if report.save
          # Broadcast to Election Day dashboard subscribers.
          CampaignBroadcast.poll_report(report)

          render json: {
            message: "Report submitted for Precinct #{precinct.number}",
            report: {
              id: report.id,
              precinct_number: precinct.number,
              village_name: precinct.village.name,
              voter_count: report.voter_count,
              report_type: report.report_type,
              reported_at: report.reported_at.iso8601
            }
          }, status: :created
        else
          render json: { errors: report.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/poll_watcher/precinct/:id/history
      def history
        precinct = precinct_scope_for_current_user.find_by(id: params[:id])
        unless precinct
          return render_api_error(
            message: "Not authorized for this precinct",
            status: :forbidden,
            code: "precinct_not_authorized"
          )
        end

        reports = active_election_event ? precinct.poll_reports.for_election(active_election_event).chronological.limit(50) : PollReport.none

        render json: {
          compliance_note: dpg_operations_compliance_note,
          election_day: election_day_payload,
          precinct: {
            id: precinct.id,
            number: precinct.number,
            village_name: precinct.village.name,
            registered_voters: precinct.registered_voters
          },
          reports: reports.map { |r|
            {
              id: r.id,
              voter_count: r.voter_count,
              report_type: r.report_type,
              notes: r.notes,
              reported_at: r.reported_at.iso8601
            }
          }
        }
      end

      # GET /api/v1/poll_watcher/strike_list?precinct_id=123&turnout_status=not_yet_voted&search=john
      def strike_list
        unless active_election_event
          return render_api_error(
            message: "A training or live election must be current before the strike list can be viewed",
            status: :unprocessable_entity,
            code: "current_election_required"
          )
        end

        precinct = resolve_accessible_precinct_from_params
        return unless precinct

        voters_scope = gec_voters_scope_for_precinct(precinct.id)
        voters_scope = apply_strike_list_search(voters_scope, params[:search]) if params[:search].present?
        voters_scope = apply_effective_turnout_filter(voters_scope, params[:turnout_status])

        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = [ per_page, 100 ].min
        total = voters_scope.count
        voters = voters_scope
          .includes(:precinct, :village)
          .limit(per_page)
          .offset((page - 1) * per_page)
          .to_a
        turnout_records = election_turnout_records_for(voters)
        external_matches, external_records = external_strike_list_matches_with_records(precinct, params[:search], params[:turnout_status])
        overlays = supporter_overlays_for_voter_ids(voters.map(&:id) + external_matches.map(&:id))

        render json: {
          compliance_note: dpg_operations_compliance_note,
          election_day: election_day_payload,
          precinct: {
            id: precinct.id,
            number: precinct.number,
            village_id: precinct.village_id,
            village_name: precinct.village.name
          },
          voters: voters.map { |voter| strike_list_voter_payload(voter, overlays[voter.id] || [], turnout_record: turnout_records[voter.id]) },
          external_matches: external_matches.map { |voter| strike_list_voter_payload(voter, overlays[voter.id] || [], observation_precinct: precinct, turnout_record: external_records[voter.id]) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            pages: (total.to_f / per_page).ceil
          }
        }
      end

      # PATCH /api/v1/poll_watcher/strike_list/:voter_id/turnout
      def update_turnout
        unless active_election_event
          return render_api_error(
            message: "A training or live election must be current before turnout can be updated",
            status: :unprocessable_entity,
            code: "current_election_required"
          )
        end

        precinct = resolve_accessible_precinct_for_turnout!
        return unless precinct

        voter = find_accessible_gec_voter!(
          params[:voter_id],
          precinct,
          turnout_update_params[:turnout_status]
        )
        return unless voter

        original_turnout_status = active_election_event.election_turnout_records
          .where(gec_voter_id: voter.id)
          .pick(:turnout_status) || "not_yet_voted"
        result = ElectionTurnoutUpdateService.new(
          election_event: active_election_event,
          gec_voter: voter,
          actor_user: current_user,
          turnout_status: turnout_update_params[:turnout_status],
          note: turnout_update_params[:note],
          source: turnout_source_for_current_user,
          observation_precinct: precinct
        ).call

        if result.success?
          overlays = supporter_overlays_for_voter_ids([ voter.id ])
          render json: {
            message: "Voter turnout status updated",
            compliance_note: dpg_operations_compliance_note,
            voter: strike_list_voter_payload(voter.reload, overlays[voter.id] || [], observation_precinct: precinct, turnout_record: result.respond_to?(:record) ? result.record : nil),
            changed: {
              turnout_status: [ original_turnout_status, result.record.turnout_status ]
            }
          }
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      private

      def report_params
        params.require(:report).permit(:precinct_id, :voter_count, :report_type, :notes)
      end

      def turnout_update_params
        params.require(:turnout).permit(:precinct_id, :turnout_status, :note)
      end

      def resolve_accessible_precinct_for_turnout!
        precinct_id = turnout_update_params[:precinct_id]
        unless precinct_id.present?
          render_api_error(
            message: "precinct_id is required",
            status: :unprocessable_entity,
            code: "precinct_id_required"
          )
          return nil
        end

        precinct = precinct_scope_for_current_user.includes(:village).find_by(id: precinct_id)
        if precinct.nil?
          render_api_error(
            message: "Not authorized for this precinct",
            status: :forbidden,
            code: "precinct_not_authorized"
          )
          return nil
        end

        precinct
      end

      def resolve_accessible_precinct_from_params
        precinct_id = params[:precinct_id]
        unless precinct_id.present?
          render_api_error(
            message: "precinct_id is required",
            status: :unprocessable_entity,
            code: "precinct_id_required"
          )
          return nil
        end

        precinct = precinct_scope_for_current_user.includes(:village).find_by(id: precinct_id)
        if precinct.nil?
          render_api_error(
            message: "Not authorized for this precinct",
            status: :forbidden,
            code: "precinct_not_authorized"
          )
          return nil
        end

        precinct
      end

      def apply_strike_list_search(scope, raw_search)
        terms = raw_search.to_s.downcase.strip.split(/\s+/).map(&:presence).compact.uniq.first(8)
        return scope if terms.empty?

        terms.reduce(scope) do |filtered_scope, term|
          query = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
          filtered_scope.where(
            <<~SQL.squish,
              LOWER(COALESCE(first_name, '')) LIKE :q
              OR LOWER(COALESCE(middle_name, '')) LIKE :q
              OR LOWER(COALESCE(last_name, '')) LIKE :q
              OR LOWER(COALESCE(address, '')) LIKE :q
              OR LOWER(COALESCE(voter_registration_number, '')) LIKE :q
              OR LOWER(TRIM(CONCAT_WS(' ', COALESCE(first_name, ''), COALESCE(middle_name, ''), COALESCE(last_name, '')))) LIKE :q
              OR LOWER(TRIM(CONCAT_WS(' ', COALESCE(last_name, ''), COALESCE(first_name, ''), COALESCE(middle_name, '')))) LIKE :q
              OR LOWER(TRIM(CONCAT(COALESCE(last_name, ''), ', ', COALESCE(first_name, ''), CASE WHEN COALESCE(middle_name, '') = '' THEN '' ELSE ' ' || COALESCE(middle_name, '') END))) LIKE :q
            SQL
            q: query
          )
        end
      end

      def gec_voters_scope_for_precinct(precinct_id)
        election_gec_voter_scope
          .where(precinct_id: precinct_id)
          .order(:last_name, :first_name, :id)
      end

      def election_gec_voter_scope
        scope = GecVoter.active
        if active_election_event&.gec_list_date.present?
          scope.for_list_date(active_election_event.gec_list_date)
        else
          GecVoter.election_day_active
        end
      end

      def election_turnout_records_for(voters)
        return {} if active_election_event.blank? || voters.blank?

        existing = active_election_event.election_turnout_records.where(gec_voter_id: voters.map(&:id)).index_by(&:gec_voter_id)
        voters.each_with_object({}) do |voter, memo|
          memo[voter.id] = existing[voter.id] || ElectionTurnoutRecord.build_for_display(election_event: active_election_event, gec_voter: voter)
        end
      end

      def apply_effective_turnout_filter(scope, turnout_status)
        return scope if turnout_status.blank?

        if active_election_event.present?
          join_sql = ActiveRecord::Base.sanitize_sql_array([
            "LEFT OUTER JOIN election_turnout_records turnout_filter_records ON turnout_filter_records.gec_voter_id = gec_voters.id AND turnout_filter_records.election_event_id = ?",
            active_election_event.id
          ])
          scope.joins(join_sql).where("COALESCE(turnout_filter_records.turnout_status, 'not_yet_voted') = ?", turnout_status)
        else
          scope.where(turnout_status: turnout_status)
        end
      end

      def effective_turnout_status(voter, turnout_record)
        active_election_event.present? ? (turnout_record&.turnout_status || "not_yet_voted") : voter.turnout_status
      end

      def external_strike_list_matches_with_records(precinct, raw_search, turnout_status)
        return [ [], {} ] if raw_search.to_s.strip.blank?

        matches = election_gec_voter_scope.where.not(precinct_id: precinct.id)
        matches = apply_strike_list_search(matches, raw_search)
        matches = apply_effective_turnout_filter(matches, turnout_status)
        candidates = matches
          .includes(:precinct, :village)
          .order(:last_name, :first_name, :id)
          .limit(10)
          .to_a
        [ candidates, election_turnout_records_for(candidates) ]
      end

      def find_accessible_gec_voter!(voter_id, precinct, requested_turnout_status)
        voter = election_gec_voter_scope.find_by(id: voter_id)
        if voter.nil?
          return render_voter_not_found!(requested_turnout_status)
        end

        return voter if voter.precinct_id == precinct.id

        # Keep poll-watcher writes strictly scoped to assigned precinct rows. Out-of-precinct
        # observations are useful for reconciliation, but only admins/coordinators may alter
        # those voter records directly; poll watchers should file a Name Not On List incident.
        if requested_turnout_status == "observed_elsewhere" || voter.turnout_status == "observed_elsewhere"
          return voter if can_reconcile_cross_precinct_turnout?
        end

        render_voter_not_found!(requested_turnout_status)
      end

      def render_voter_not_found!(requested_turnout_status)
        render_api_error(
          message: requested_turnout_status == "observed_elsewhere" ? "Voter not found in election-day voter list" : "Voter not found in this precinct",
          status: :not_found,
          code: "voter_not_found"
        )
        nil
      end

      def turnout_source_for_current_user
        return "poll_watcher" if current_user.poll_watcher?

        "admin_override"
      end

      def can_reconcile_cross_precinct_turnout?
        current_user.admin? || current_user.coordinator?
      end

      def dpg_operations_compliance_note
        "DPG operations tracking only; not official election records."
      end

      def supporter_overlays_for_voter_ids(voter_ids)
        return {} if voter_ids.blank?

        Supporter
          .contacts
          .includes(:village, :precinct)
          .where(gec_voter_id: voter_ids)
          .order(:print_name)
          .group_by(&:gec_voter_id)
      end

      def strike_list_voter_payload(voter, linked_supporters, observation_precinct: nil, turnout_record: nil)
        out_of_precinct = observation_precinct.present? && voter.precinct_id != observation_precinct.id
        effective_status = effective_turnout_status(voter, turnout_record)

        {
          id: voter.id,
          first_name: voter.first_name,
          middle_name: voter.middle_name,
          last_name: voter.last_name,
          print_name: NameParser.combine(
            first_name: voter.first_name,
            middle_name: voter.middle_name,
            last_name: voter.last_name,
            format: :last_comma_first
          ),
          voter_registration_number: voter.voter_registration_number,
          address: voter.address,
          precinct_id: voter.precinct_id,
          precinct_number: voter.precinct_number || voter.precinct&.number,
          village_name: voter.village_name || voter.village&.name,
          out_of_precinct: out_of_precinct,
          turnout_status: effective_status,
          turnout_source: turnout_record&.turnout_source || voter.turnout_source,
          turnout_note: turnout_record&.turnout_note || voter.turnout_note,
          turnout_updated_at: (turnout_record&.turnout_updated_at || voter.turnout_updated_at)&.iso8601,
          supporter_overlay: supporter_overlay_payload(linked_supporters)
        }
      end

      def supporter_overlay_payload(linked_supporters)
        return nil if linked_supporters.blank?

        {
          supporter_count: linked_supporters.size,
          village_names: linked_supporters.map { |supporter| supporter.village&.name }.compact.uniq.sort,
          precinct_numbers: linked_supporters.map { |supporter| supporter.precinct&.number }.compact.uniq.sort
        }
      end

      def precinct_scope_for_current_user
        scope = Precinct.all

        if current_user.admin?
          scope
        elsif current_user.coordinator?
          current_user.assigned_district_id.present? ? scope.joins(:village).where(villages: { district_id: current_user.assigned_district_id }) : scope
        elsif current_user.poll_watcher?
          assigned_precinct_ids = current_user.poll_watcher_precinct_assignments.pluck(:precinct_id)
          assigned_precinct_ids.any? ? scope.where(id: assigned_precinct_ids) : scope.none
        else
          scope.none
        end
      end

      def active_election_event
        @active_election_event ||= ElectionEvent.current_event
      end

      def election_day_payload
        active_import = active_election_event&.gec_import || GecImport.active_election_day_import
        {
          election_event_id: active_election_event&.id,
          election_name: active_election_event&.name,
          election_date: active_election_event&.election_date&.iso8601,
          election_status: active_election_event&.status,
          list_date: (active_election_event&.gec_list_date || GecVoter.election_day_list_date)&.iso8601,
          active_import_id: active_import&.id,
          active_import_filename: active_import&.filename,
          active_import_set_at: active_import&.activated_for_election_at&.iso8601,
          active_import_explicit: active_import.present?,
          setup_required: active_election_event.blank?,
          precinct_assignment_required: poll_watcher_precinct_assignment_required?
        }
      end

      def poll_watcher_precinct_assignment_required?
        current_user.poll_watcher? && !current_user.poll_watcher_precinct_assignments.exists?
      end
    end
  end
end
