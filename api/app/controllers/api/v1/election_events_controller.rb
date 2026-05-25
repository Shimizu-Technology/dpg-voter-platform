# frozen_string_literal: true

module Api
  module V1
    class ElectionEventsController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_election_day_admin_access!, except: [ :index, :show ]
      before_action :require_command_center_access!, only: [ :index, :show ]

      def index
        events = ElectionEvent.includes(:gec_import).recent_first.limit(25)
        render json: {
          active_election: election_event_json(ElectionEvent.active_event),
          election_events: events.map { |event| election_event_json(event) },
          completed_gec_imports: GecImport.completed.latest.limit(25).map { |gec_import| gec_import_json(gec_import) }
        }
      end

      def show
        event = ElectionEvent.includes(:gec_import).find(params[:id])
        render json: { election_event: election_event_json(event) }
      end

      def create
        event = ElectionEvent.new(election_event_params)
        if event.save
          log_audit!(event, action: "election_event_created", changed_data: event.saved_changes.except("created_at", "updated_at"))
          render json: { election_event: election_event_json(event) }, status: :created
        else
          render_api_error(message: event.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "election_event_create_failed")
        end
      end

      def update
        event = ElectionEvent.find(params[:id])
        before = event.attributes.slice("name", "election_type", "election_date", "status", "gec_import_id")
        if event.update(election_event_params)
          changes = before.each_with_object({}) do |(key, value), memo|
            next if event.public_send(key) == value

            memo[key] = [ value, event.public_send(key) ]
          end
          log_audit!(event, action: "election_event_updated", changed_data: changes) if changes.any?
          render json: { election_event: election_event_json(event) }
        else
          render_api_error(message: event.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "election_event_update_failed")
        end
      end

      def activate
        event = ElectionEvent.find(params[:id])
        unless event.gec_import&.completed?
          return render_api_error(message: "Select a completed GEC import before activating this election", status: :unprocessable_entity, code: "missing_active_gec_import")
        end

        event.activate!(actor_user: current_user)
        log_audit!(event, action: "election_event_activated", changed_data: { status: [ nil, "active" ], gec_import_id: event.gec_import_id })
        render json: { election_event: election_event_json(event.reload) }
      end

      def close
        event = ElectionEvent.find(params[:id])
        event.close!(actor_user: current_user)
        log_audit!(event, action: "election_event_closed", changed_data: { status: [ nil, "closed" ] })
        render json: { election_event: election_event_json(event.reload) }
      end

      private

      def election_event_params
        params.require(:election_event).permit(:name, :election_type, :election_date, :status, :gec_import_id)
      end

      def require_command_center_access!
        return if current_user&.admin? || current_user&.data_team? || current_user&.coordinator?

        render_api_error(message: "Election Day setup access required", status: :forbidden, code: "election_day_setup_access_required")
      end

      def require_election_day_admin_access!
        return if current_user&.admin? || current_user&.data_team?

        render_api_error(message: "Election Day setup management requires Administrator or Data Manager access", status: :forbidden, code: "election_day_setup_management_required")
      end

      def election_event_json(event)
        return nil unless event

        {
          id: event.id,
          name: event.name,
          election_type: event.election_type,
          election_date: event.election_date&.iso8601,
          status: event.status,
          gec_import_id: event.gec_import_id,
          gec_list_date: event.gec_list_date&.iso8601,
          gec_import_filename: event.gec_import&.filename,
          activated_at: event.activated_at&.iso8601,
          closed_at: event.closed_at&.iso8601,
          turnout_records_count: event.election_turnout_records.count
        }
      end

      def gec_import_json(gec_import)
        {
          id: gec_import.id,
          filename: gec_import.filename,
          gec_list_date: gec_import.gec_list_date&.iso8601,
          status: gec_import.status,
          active_election_day: gec_import.active_election_day,
          total_records: gec_import.total_records,
          created_at: gec_import.created_at&.iso8601
        }
      end
    end
  end
end
