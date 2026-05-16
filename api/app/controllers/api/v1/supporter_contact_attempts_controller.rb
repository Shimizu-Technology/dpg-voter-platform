# frozen_string_literal: true

module Api
  module V1
    class SupporterContactAttemptsController < ApplicationController
      include Authenticatable
      include AuditLoggable

      before_action :authenticate_request
      before_action :require_supporter_access!
      before_action :set_supporter
      before_action :set_contact_attempt, only: [ :update ]

      def index
        attempts = @supporter.supporter_contact_attempts
          .includes(:recorded_by_user)
          .order(recorded_at: :desc, id: :desc)
          .limit(100)

        render json: {
          contact_attempts: attempts.map { |attempt| attempt_json(attempt) },
          options: {
            channels: SupporterContactAttempt::CHANNELS,
            outcomes: SupporterContactAttempt::OUTCOMES
          }
        }
      end

      def create
        attempt = @supporter.supporter_contact_attempts.build(contact_attempt_params)
        attempt.recorded_by_user = current_user
        attempt.recorded_at ||= Time.current

        if attempt.save
          log_audit!(@supporter, action: "contact_attempt_logged", changed_data: {
            contact_attempt_id: attempt.id,
            channel: attempt.channel,
            outcome: attempt.outcome,
            recorded_at: attempt.recorded_at&.iso8601
          })
          render json: { contact_attempt: attempt_json(attempt) }, status: :created
        else
          render_api_error(
            message: attempt.errors.full_messages.to_sentence,
            status: :unprocessable_entity,
            code: "contact_attempt_create_failed"
          )
        end
      end

      def update
        return render_contact_attempt_edit_error unless can_edit_contact_attempts?

        before = contact_attempt_audit_snapshot(@contact_attempt)
        if @contact_attempt.update(contact_attempt_params)
          after = contact_attempt_audit_snapshot(@contact_attempt)
          changed_data = contact_attempt_changed_data(before, after)
          log_audit!(@supporter, action: "contact_attempt_updated", changed_data: changed_data) if changed_data.any?
          render json: { contact_attempt: attempt_json(@contact_attempt) }
        else
          render_api_error(
            message: @contact_attempt.errors.full_messages.to_sentence,
            status: :unprocessable_entity,
            code: "contact_attempt_update_failed"
          )
        end
      end

      private

      def set_supporter
        @supporter = scope_supporters(Supporter.contacts).find_by(id: params[:supporter_id])
        return if @supporter

        render_api_error(message: "Contact not found", status: :not_found, code: "not_found")
      end

      def set_contact_attempt
        @contact_attempt = @supporter.supporter_contact_attempts.find_by(id: params[:id])
        return if @contact_attempt

        render_api_error(message: "Contact attempt not found", status: :not_found, code: "contact_attempt_not_found")
      end

      def contact_attempt_params
        permitted = params.require(:contact_attempt).permit(:channel, :outcome, :note, :recorded_at)
        permitted[:recorded_at] = parsed_recorded_at(permitted[:recorded_at]) if permitted.key?(:recorded_at)
        permitted
      end

      def parsed_recorded_at(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def render_contact_attempt_edit_error
        render_api_error(
          message: "Contact history edit access required",
          status: :forbidden,
          code: "contact_attempt_edit_access_required"
        )
      end

      def contact_attempt_audit_snapshot(attempt)
        {
          channel: attempt.channel,
          outcome: attempt.outcome,
          note: attempt.note,
          recorded_at: attempt.recorded_at&.iso8601
        }
      end

      def contact_attempt_changed_data(before, after)
        before.each_with_object({}) do |(field, before_value), memo|
          after_value = after[field]
          memo[field] = [ before_value, after_value ] unless before_value == after_value
        end
      end

      def attempt_json(attempt)
        {
          id: attempt.id,
          channel: attempt.channel,
          outcome: attempt.outcome,
          note: attempt.note,
          recorded_at: attempt.recorded_at&.iso8601,
          recorded_by_user_id: attempt.recorded_by_user_id,
          recorded_by_name: attempt.recorded_by_user&.name,
          recorded_by_email: attempt.recorded_by_user&.email,
          created_at: attempt.created_at&.iso8601
        }
      end
    end
  end
end
