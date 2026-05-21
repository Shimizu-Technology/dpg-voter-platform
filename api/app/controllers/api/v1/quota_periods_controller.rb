# frozen_string_literal: true

module Api
  module V1
    class QuotaPeriodsController < ApplicationController
      include Authenticatable
      include AuditLoggable

      before_action :authenticate_request
      before_action :require_period_access!
      before_action :find_quota_period, only: [ :show, :update, :activate, :archive ]

      # GET /api/v1/quota_periods
      def index
        periods = QuotaPeriod.includes(:campaign_cycle).visible.ordered
        active_period = QuotaPeriod.active_for

        render json: {
          quota_periods: periods.map { |period| quota_period_json(period) },
          active_quota_period: active_period && quota_period_json(active_period)
        }
      end

      # GET /api/v1/quota_periods/:id
      def show
        render json: { quota_period: quota_period_json(@quota_period, include_breakdown: true) }
      end

      # POST /api/v1/quota_periods
      def create
        period = QuotaPeriod.new(quota_period_params)
        period.campaign_cycle ||= CampaignCycle.current_or_create_default!
        period.due_date ||= period.end_date
        period.quota_target ||= 0

        if period.save
          log_audit!(period, action: "quota_period_created", changed_data: quota_period_json(period))
          render json: { quota_period: quota_period_json(period) }, status: :created
        else
          render_api_error(message: period.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "quota_period_create_failed")
        end
      end

      # PATCH /api/v1/quota_periods/:id
      def update
        if @quota_period.update(quota_period_params)
          log_audit!(@quota_period, action: "quota_period_updated", changed_data: @quota_period.saved_changes.except("updated_at"), normalize: true)
          render json: { quota_period: quota_period_json(@quota_period.reload) }
        else
          render_api_error(message: @quota_period.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "quota_period_update_failed")
        end
      end

      # POST /api/v1/quota_periods/:id/activate
      def activate
        @quota_period.activate!
        log_audit!(@quota_period, action: "quota_period_activated", changed_data: { status: "open" })
        render json: { quota_period: quota_period_json(@quota_period.reload) }
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(message: e.record.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "quota_period_activate_failed")
      end

      # POST /api/v1/quota_periods/:id/archive
      def archive
        @quota_period.archive!
        log_audit!(@quota_period, action: "quota_period_archived", changed_data: { status: "archived" })
        render json: { quota_period: quota_period_json(@quota_period.reload) }
      end

      private

      def require_period_access!
        return if current_user&.admin? || current_user&.data_team? || current_user&.coordinator?

        render_api_error(message: "Periods & Goals access required", status: :forbidden, code: "quota_period_access_required")
      end

      def find_quota_period
        @quota_period = QuotaPeriod.find_by(id: params[:id])
        return if @quota_period

        render_api_error(message: "Quota period not found", status: :not_found, code: "quota_period_not_found")
      end

      def quota_period_params
        params.require(:quota_period).permit(:name, :start_date, :end_date, :due_date, :quota_target, :status)
      end

      def quota_period_json(period, include_breakdown: false)
        counts = period_counts(period)
        payload = {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date,
          due_date: period.due_date,
          quota_target: period.quota_target,
          status: period.status,
          active: period == QuotaPeriod.active_for,
          campaign_cycle_id: period.campaign_cycle_id,
          campaign_cycle_name: period.campaign_cycle&.name,
          counts: counts,
          created_at: period.created_at&.iso8601,
          updated_at: period.updated_at&.iso8601
        }
        payload[:village_counts] = village_counts(period) if include_breakdown
        payload
      end

      def period_counts(period)
        scope = Supporter.where(quota_period_id: period.id)
        {
          total_contacts: scope.contacts.count,
          pending_intake: scope.intake.count,
          active_contacts: scope.relationship_contacts.count,
          supporters: scope.classified_supporters.count,
          qr_signups: scope.where(source: "qr_signup").count,
          public_signups: scope.public_origin.count,
          staff_entries: scope.where(source: "staff_entry").count
        }
      end

      def village_counts(period)
        Supporter.where(quota_period_id: period.id)
          .joins(:village)
          .group("villages.id", "villages.name")
          .order("villages.name ASC")
          .count
          .map do |(village_id, village_name), total|
            { village_id: village_id, village_name: village_name, total_contacts: total }
          end
      end

      def audit_entry_mode
        "quota_periods"
      end
    end
  end
end
