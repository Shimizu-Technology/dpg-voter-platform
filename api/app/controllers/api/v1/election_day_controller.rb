# frozen_string_literal: true

module Api
  module V1
    class ElectionDayController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_command_center_access!

      def show
        event = current_election_event
        unless event
          return render json: {
            setup_required: true,
            message: "Create and activate an election event before using the Election Day Command Center.",
            active_election: nil
          }
        end

        query = ElectionDayCommandCenterQuery.new(event: event, params: command_center_params)
        chase = query.chase_page
        exceptions = exception_payloads(event)

        render json: {
          setup_required: false,
          compliance_note: dpg_operations_compliance_note,
          active_election: election_event_json(event),
          stats: query.stats,
          villages: query.villages,
          chase_list: chase[:records],
          chase_pagination: chase[:pagination],
          exceptions: exceptions,
          recent_reports: recent_reports(event)
        }
      end

      def log_contact
        event = current_election_event
        return render_api_error(message: "No active election event", status: :unprocessable_entity, code: "active_election_required") unless event

        supporter = Supporter.contacts.find_by(id: params[:supporter_id], gec_voter_id: election_voters(event).select(:id))
        return render_api_error(message: "Contact not found on this election's GEC list", status: :not_found, code: "supporter_not_found") unless supporter

        attempt = supporter.supporter_contact_attempts.build(contact_attempt_params)
        attempt.recorded_by_user = current_user
        # Election Day chase-list contact state should reflect when the command center logged the touch,
        # not a client-supplied timestamp that could hide/show the row under "contacted today" incorrectly.
        attempt.recorded_at = Time.current
        attempt.note = election_contact_note(event, attempt.note)

        if attempt.save
          log_audit!(supporter, action: "election_day_contact_logged", changed_data: {
            contact_attempt_id: attempt.id,
            channel: attempt.channel,
            outcome: attempt.outcome,
            election_event_id: event.id
          })
          render json: { contact_attempt: contact_attempt_summary_json(attempt) }, status: :created
        else
          render_api_error(message: attempt.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "election_day_contact_failed")
        end
      end

      private

      def require_command_center_access!
        return if current_user&.admin? || current_user&.data_team? || current_user&.coordinator?

        render_api_error(message: "Election Day Command Center access required", status: :forbidden, code: "command_center_access_required")
      end

      def current_election_event
        @current_election_event ||= ElectionEvent.current_event
      end

      def election_voters(event)
        scope = GecVoter.active
        event.gec_list_date.present? ? scope.for_list_date(event.gec_list_date) : scope.election_day_active
      end

      def exception_payloads(event)
        records = event.election_turnout_records
          .observed_elsewhere
          .includes(:gec_voter, :observation_precinct)
          .order(updated_at: :desc)
          .limit(100)

        records.map do |record|
          voter = record.gec_voter
          {
            id: record.id,
            gec_voter_id: voter.id,
            name: NameParser.combine(first_name: voter.first_name, middle_name: voter.middle_name, last_name: voter.last_name, format: :last_comma_first),
            registered_village: record.registered_village_name,
            registered_precinct: record.registered_precinct_number,
            observed_village: record.observation_village_name,
            observed_precinct: record.observation_precinct_number,
            note: record.turnout_note,
            updated_at: record.turnout_updated_at&.iso8601
          }
        end
      end

      def recent_reports(event)
        PollReport.for_election(event).includes(:user, precinct: :village).order(reported_at: :desc).limit(25).map do |report|
          {
            id: report.id,
            precinct_id: report.precinct_id,
            precinct_number: report.precinct&.number,
            village_name: report.precinct&.village&.name,
            report_type: report.report_type,
            voter_count: report.voter_count,
            notes: report.notes,
            reported_at: report.reported_at&.iso8601,
            user_name: report.user&.name
          }
        end
      end

      def command_center_params
        params.permit(:village, :search, :contact_filter, :chase_page, :chase_per_page)
      end

      def election_contact_note(event, note)
        base = "Election Day follow-up for #{event.name}"
        plain = note.to_s.strip
        plain.present? ? "#{base}: #{plain}" : base
      end

      def contact_attempt_params
        params.require(:contact_attempt).permit(:channel, :outcome, :note)
      end

      def dpg_operations_compliance_note
        "DPG operations tracking only; not official election records."
      end

      def election_event_json(event)
        {
          id: event.id,
          name: event.name,
          election_type: event.election_type,
          election_date: event.election_date&.iso8601,
          status: event.status,
          gec_import_id: event.gec_import_id,
          gec_list_date: event.gec_list_date&.iso8601,
          gec_import_filename: event.gec_import&.filename
        }
      end
    end
  end
end
