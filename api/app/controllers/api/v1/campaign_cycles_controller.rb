# frozen_string_literal: true

module Api
  module V1
    class CampaignCyclesController < ApplicationController
      include Authenticatable

      before_action :authenticate_request
      before_action :set_campaign_cycle, only: %i[update destroy]

      # GET /api/v1/campaign_cycles
      def index
        cycles = CampaignCycle.order(start_date: :desc)
        cycles = cycles.where(status: params[:status]) if params[:status].present?

        render json: {
          campaign_cycles: cycles.as_json(include: {
            quota_periods: { only: [ :id, :name, :start_date, :end_date, :due_date, :quota_target, :status ] }
          })
        }
      end

      # GET /api/v1/campaign_cycles/current
      def current
        cycle = CampaignCycle.current.order(start_date: :desc, id: :desc).first

        unless cycle
          render json: { campaign_cycle: nil, message: "No active campaign cycle" }
          return
        end

        period = cycle.current_period

        render json: {
          campaign_cycle: cycle.as_json,
          current_period: period ? period_json(period) : nil,
          periods: cycle.quota_periods.order(:start_date).map { |p| period_summary_json(p) }
        }
      end

      # POST /api/v1/campaign_cycles
      def create
        require_admin!

        cycle = CampaignCycle.new(campaign_cycle_params)

        if cycle.save
          # Auto-generate monthly periods if requested
          if ActiveModel::Type::Boolean.new.cast(params.fetch(:generate_periods, true))
            village_targets = (params[:village_targets] || {}).permit!.to_h.transform_keys(&:to_i)
            cycle.generate_periods!(village_targets: village_targets)
          end

          render json: { campaign_cycle: cycle.as_json(include: :quota_periods) }, status: :created
        else
          render json: { errors: cycle.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/campaign_cycles/:id
      def update
        require_admin!

        if @campaign_cycle.update(campaign_cycle_params)
          render json: { campaign_cycle: @campaign_cycle.as_json(include: :quota_periods) }
        else
          render json: { errors: @campaign_cycle.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/campaign_cycles/:id
      def destroy
        require_admin!

        @campaign_cycle.update!(status: "archived")
        render json: { message: "Campaign cycle archived" }
      end

      private

      def set_campaign_cycle
        @campaign_cycle = CampaignCycle.find(params[:id])
      end

      def campaign_cycle_params
        params.permit(:name, :cycle_type, :start_date, :end_date, :status,
                       :carry_forward_data, :monthly_quota_target, settings: {})
      end

      def period_json(period)
        {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date,
          due_date: period.due_date,
          quota_target: period.effective_quota_target,
          status: period.status,
          official_count: period.total_assigned,
          matched_count: period.matched_count,
          eligible_count: period.eligible_count,
          total_assigned: period.total_assigned,
          days_until_due: period.days_until_due,
          overdue: period.overdue?,
          due_soon: period.due_soon?,
          editable: period.editable?,
          locked: period.locked?,
          village_breakdown: period.village_breakdown
        }
      end

      def period_summary_json(period)
        {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date,
          due_date: period.due_date,
          quota_target: period.effective_quota_target,
          status: period.status,
          official_count: period.total_assigned,
          matched_count: period.matched_count,
          eligible_count: period.eligible_count,
          days_until_due: period.days_until_due,
          overdue: period.overdue?,
          due_soon: period.due_soon?,
          editable: period.editable?,
          locked: period.locked?
        }
      end
    end
  end
end
