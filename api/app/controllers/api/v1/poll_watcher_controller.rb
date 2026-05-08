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
        latest_reports = PollReport.today
          .latest_per_precinct
          .where(precinct_id: accessible_precincts.select(:id))
          .index_by(&:precinct_id)

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
        report.reported_at = Time.current

        if report.save
          # Broadcast to war room / dashboard
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

        reports = precinct.poll_reports.today.chronological.limit(50)

        render json: {
          compliance_note: campaign_operations_compliance_note,
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
        precinct = resolve_accessible_precinct_from_params
        return unless precinct

        voters = gec_voters_scope_for_precinct(precinct.id)
        voters = voters.where(turnout_status: params[:turnout_status]) if params[:turnout_status].present?

        voters = apply_strike_list_search(voters, params[:search]) if params[:search].present?
        external_matches = external_strike_list_matches(precinct, params[:search], params[:turnout_status])

        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = [ per_page, 100 ].min
        total = voters.count
        voters = voters.offset((page - 1) * per_page).limit(per_page).to_a
        overlays = supporter_overlays_for_voter_ids(voters.map(&:id) + external_matches.map(&:id))

        render json: {
          compliance_note: campaign_operations_compliance_note,
          election_day: election_day_payload,
          precinct: {
            id: precinct.id,
            number: precinct.number,
            village_id: precinct.village_id,
            village_name: precinct.village.name
          },
          voters: voters.map { |voter| strike_list_voter_payload(voter, overlays[voter.id] || []) },
          external_matches: external_matches.map { |voter| strike_list_voter_payload(voter, overlays[voter.id] || [], observation_precinct: precinct) },
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
        precinct = resolve_accessible_precinct_for_turnout!
        return unless precinct

        voter = find_accessible_gec_voter!(
          params[:voter_id],
          precinct,
          turnout_update_params[:turnout_status]
        )
        return unless voter

        original_turnout_status = voter.turnout_status
        result = GecVoterTurnoutService.new(
          gec_voter: voter,
          actor_user: current_user,
          turnout_status: turnout_update_params[:turnout_status],
          note: turnout_update_params[:note],
          source: turnout_source_for_current_user,
          observation_precinct: precinct
        )
          .call

        if result.success?
          overlays = supporter_overlays_for_voter_ids([ voter.id ])
          render json: {
            message: "Voter turnout status updated",
            compliance_note: campaign_operations_compliance_note,
            voter: strike_list_voter_payload(voter.reload, overlays[voter.id] || [], observation_precinct: precinct),
            changed: {
              turnout_status: [ original_turnout_status, voter.turnout_status ]
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
        GecVoter
          .election_day_active
          .where(precinct_id: precinct_id)
          .order(:last_name, :first_name, :id)
      end

      def external_strike_list_matches(precinct, raw_search, turnout_status)
        return [] if raw_search.to_s.strip.blank?

        matches = GecVoter
          .election_day_active
          .where.not(precinct_id: precinct.id)
        matches = matches.where(turnout_status: turnout_status) if turnout_status.present?
        matches = apply_strike_list_search(matches, raw_search)
        matches
          .includes(:precinct, :village)
          .order(:last_name, :first_name, :id)
          .limit(10)
          .to_a
      end

      def find_accessible_gec_voter!(voter_id, precinct, requested_turnout_status)
        voter = GecVoter.election_day_active.find_by(id: voter_id)
        if voter.nil?
          return render_voter_not_found!(requested_turnout_status)
        end

        return voter if voter.precinct_id == precinct.id
        return voter if requested_turnout_status == "observed_elsewhere"
        return voter if voter.turnout_status == "observed_elsewhere" && can_reconcile_cross_precinct_turnout?

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

      def campaign_operations_compliance_note
        "Campaign operations tracking only; not official election records."
      end

      def supporter_overlays_for_voter_ids(voter_ids)
        return {} if voter_ids.blank?

        Supporter
          .working_supporters
          .where(gec_voter_id: voter_ids)
          .order(:print_name)
          .group_by(&:gec_voter_id)
      end

      def strike_list_voter_payload(voter, linked_supporters, observation_precinct: nil)
        out_of_precinct = observation_precinct.present? && voter.precinct_id != observation_precinct.id

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
          turnout_status: voter.turnout_status,
          turnout_source: voter.turnout_source,
          turnout_note: voter.turnout_note,
          turnout_updated_at: voter.turnout_updated_at&.iso8601,
          supporter_overlay: linked_supporters.present? ? { supporter_count: linked_supporters.size } : nil
        }
      end

      def precinct_scope_for_current_user
        scope = Precinct.all

        if current_user.admin?
          scope
        elsif current_user.coordinator?
          current_user.assigned_district_id.present? ? scope.joins(:village).where(villages: { district_id: current_user.assigned_district_id }) : scope
        elsif current_user.poll_watcher?
          assigned_precinct_ids = current_user.poll_watcher_precinct_assignments.select(:precinct_id)
          if current_user.poll_watcher_precinct_assignments.exists?
            scope.where(id: assigned_precinct_ids)
          elsif current_user.assigned_village_id.present?
            scope.where(village_id: current_user.assigned_village_id)
          else
            scope.none
          end
        elsif current_user.chief?
          current_user.assigned_village_id.present? ? scope.where(village_id: current_user.assigned_village_id) : scope.none
        else
          scope.none
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
