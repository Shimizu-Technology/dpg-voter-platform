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

        voters = election_voters(event).includes(:village, :precinct)
        records = turnout_records_for(event, voters)
        linked_supporters = linked_supporters_for(voters.map(&:id))
        latest_attempts = LatestSupporterContactAttempts.call(linked_supporters.values.flatten, include_recorded_by: true)
        villages = village_payloads(voters, records, linked_supporters, latest_attempts)
        chase = chase_list(voters, records, linked_supporters, latest_attempts)
        exceptions = exception_payloads(event)

        render json: {
          setup_required: false,
          compliance_note: dpg_operations_compliance_note,
          active_election: election_event_json(event),
          stats: command_center_stats(voters, records, chase, exceptions),
          villages: villages,
          chase_list: chase,
          exceptions: exceptions.first(100),
          recent_reports: recent_reports(event, voters)
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
        @current_election_event ||= ElectionEvent.active_event
      end

      def election_voters(event)
        scope = GecVoter.active
        event.gec_list_date.present? ? scope.for_list_date(event.gec_list_date) : scope.election_day_active
      end

      def turnout_records_for(event, voters)
        existing = event.election_turnout_records.where(gec_voter_id: voters.select(:id)).index_by(&:gec_voter_id)
        voters.each_with_object({}) do |voter, memo|
          memo[voter.id] = existing[voter.id] || ElectionTurnoutRecord.build_for_display(election_event: event, gec_voter: voter)
        end
      end

      def linked_supporters_for(voter_ids)
        Supporter.contacts.includes(:village, :precinct).where(gec_voter_id: voter_ids).group_by(&:gec_voter_id)
      end

      def village_payloads(voters, records, linked_supporters, latest_attempts)
        voters.group_by { |voter| voter.village_name || voter.village&.name || "Unknown" }.sort_by(&:first).map do |village_name, village_voters|
          village_records = village_voters.map { |voter| records[voter.id] }
          supporters = village_voters.flat_map { |voter| linked_supporters[voter.id] || [] }
          supporter_ids = supporters.map(&:id).uniq
          contacted_today = supporter_ids.count { |id| contact_attempt_today?(latest_attempts[id]) }
          {
            name: village_name,
            total_voters: village_voters.size,
            voted: village_records.count { |record| record.turnout_status == "voted" },
            not_yet_voted: village_records.count { |record| record.turnout_status == "not_yet_voted" },
            unknown: village_records.count { |record| record.turnout_status == "unknown" },
            observed_elsewhere: village_records.count { |record| record.turnout_status == "observed_elsewhere" },
            linked_contacts: supporter_ids.size,
            linked_not_yet_voted: village_voters.count { |voter| records[voter.id].turnout_status == "not_yet_voted" && linked_supporters[voter.id].present? },
            contacted_today: contacted_today,
            not_contacted_today: [ supporter_ids.size - contacted_today, 0 ].max,
            ride_requests: supporters.count(&:needs_election_day_ride?)
          }
        end
      end

      def chase_list(voters, records, linked_supporters, latest_attempts)
        voters.flat_map do |voter|
          record = records[voter.id]
          next [] unless record.turnout_status == "not_yet_voted"

          (linked_supporters[voter.id] || []).map do |supporter|
            latest_attempt = latest_attempts[supporter.id]
            {
              supporter_id: supporter.id,
              gec_voter_id: voter.id,
              name: supporter.display_name,
              phone: supporter.contact_number,
              email: supporter.email,
              dpg_village: supporter.village&.name,
              dpg_precinct: supporter.precinct&.number,
              gec_village: voter.village_name || voter.village&.name,
              gec_precinct: voter.precinct_number || voter.precinct&.number,
              turnout_status: record.turnout_status,
              needs_ride: supporter.needs_election_day_ride,
              support_status: supporter.support_status,
              latest_contact_attempt: latest_attempt && contact_attempt_summary_json(latest_attempt),
              contacted_today: contact_attempt_today?(latest_attempt)
            }
          end
        end.compact.sort_by { |row| [ row[:contacted_today] ? 1 : 0, row[:gec_village].to_s, row[:name].to_s ] }
      end

      def exception_payloads(event)
        records = event.election_turnout_records
          .observed_elsewhere
          .includes(:gec_voter, :observation_precinct)
          .order(updated_at: :desc)

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

      def recent_reports(event, voters)
        precinct_ids = voters.map(&:precinct_id).compact.uniq
        reports = PollReport.where(reported_at: event.election_date.all_day)
        reports = reports.where(precinct_id: precinct_ids) if precinct_ids.any?

        reports.includes(:precinct, :user).order(reported_at: :desc).limit(25).map do |report|
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

      def command_center_stats(voters, records, chase, exceptions)
        record_values = records.values
        {
          total_voters: voters.size,
          voted: record_values.count { |record| record.turnout_status == "voted" },
          not_yet_voted: record_values.count { |record| record.turnout_status == "not_yet_voted" },
          unknown: record_values.count { |record| record.turnout_status == "unknown" },
          observed_elsewhere: record_values.count { |record| record.turnout_status == "observed_elsewhere" },
          chase_list_count: chase.size,
          contacted_today: chase.count { |row| row[:contacted_today] },
          not_contacted_today: chase.count { |row| !row[:contacted_today] },
          ride_requests: chase.count { |row| row[:needs_ride] },
          exceptions: exceptions.size
        }
      end

      def contact_attempt_today?(attempt)
        attempt&.recorded_at&.to_date == Time.zone.today
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
