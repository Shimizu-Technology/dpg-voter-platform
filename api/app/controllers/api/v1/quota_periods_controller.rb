# frozen_string_literal: true

module Api
  module V1
    class QuotaPeriodsController < ApplicationController
      include Authenticatable

      before_action :authenticate_request
      before_action :require_coordinator_or_above!, only: %i[show village_quotas]
      before_action :set_quota_period, only: %i[show update submit village_quotas update_village_quotas]

      # GET /api/v1/quota_periods/:id
      def show
        render json: { quota_period: period_detail_json(@quota_period) }
      end

      # PATCH /api/v1/quota_periods/:id
      def update
        require_admin!

        if @quota_period.update(quota_period_params)
          render json: { quota_period: period_detail_json(@quota_period) }
        else
          render json: { errors: @quota_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/quota_periods/:id/submit
      # Snapshot the current counts and mark as submitted
      def submit
        unless current_user&.admin? || current_user&.data_team?
          render_api_error(message: "Data team access required", status: :forbidden, code: "data_team_required")
          return
        end

        unless @quota_period.status == "open"
          render json: { error: "Only open periods can be submitted" }, status: :unprocessable_entity
          return
        end

        @quota_period.submit!
        render json: {
          quota_period: period_detail_json(@quota_period),
          message: "Period submitted successfully"
        }
      end

      # GET /api/v1/quota_periods/:id/village_quotas
      def village_quotas
        render json: {
          village_quotas: @quota_period.village_quotas.includes(:village).map { |vq|
            {
              id: vq.id,
              village_id: vq.village_id,
              village_name: vq.village&.name,
              target: vq.target,
              submitted_count: vq.submitted_count
            }
          }
        }
      end

      # PATCH /api/v1/quota_periods/:id/village_quotas
      # Bulk update village targets: { village_quotas: [{ village_id: 1, target: 300 }, ...] }
      def update_village_quotas
        require_admin!

        updates = params[:village_quotas] || []
        ActiveRecord::Base.transaction do
          updates.each do |vq_params|
            vq = @quota_period.village_quotas.find_or_initialize_by(village_id: vq_params[:village_id])
            vq.update!(target: vq_params[:target])
          end
        end

        render json: { message: "Village quotas updated", count: updates.size }
      end

      private

      def set_quota_period
        @quota_period = QuotaPeriod.find(params[:id])
      end

      def quota_period_params
        params.permit(:name, :start_date, :end_date, :due_date, :quota_target, :status)
      end

      def period_detail_json(period)
        submitted_summary = period.submission_summary.presence || {}
        historical_breakdown = submitted_summary["village_breakdown"]
        progress_count = submitted_summary["total_eligible"] || period.eligible_count
        matched_count = submitted_summary["total_matched"] || period.matched_count
        assigned_count = submitted_summary["total_assigned"] || period.total_assigned

        {
          id: period.id,
          name: period.name,
          campaign_cycle_id: period.campaign_cycle_id,
          campaign_cycle_name: period.campaign_cycle&.name,
          start_date: period.start_date,
          end_date: period.end_date,
          due_date: period.due_date,
          quota_target: period.effective_quota_target,
          status: period.status,
          eligible_count: progress_count,
          matched_count: matched_count,
          total_assigned: assigned_count,
          days_until_due: period.days_until_due,
          overdue: period.overdue?,
          due_soon: period.due_soon?,
          editable: period.editable?,
          locked: period.locked?,
          submission_summary: period.submission_summary,
          village_breakdown: historical_breakdown || period.village_breakdown
        }
      end
    end
  end
end
