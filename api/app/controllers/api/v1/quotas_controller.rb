# frozen_string_literal: true

module Api
  module V1
    class QuotasController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_coordinator_or_above!

      # GET /api/v1/quotas
      def index
        campaign = Campaign.active.first
        villages = Village.order(:name)
        current_period = CampaignCycle.current_quota_period
        current_period_targets = current_period&.effective_village_targets(include_legacy_fallback: true) || {}
        current_period_village_quotas = current_period&.village_quotas&.index_by(&:village_id) || {}
        latest_gec_list_date = GecVoter.active.maximum(:gec_list_date)
        existing_quotas = if campaign
          Quota.where(campaign_id: campaign.id, village_id: villages.pluck(:id)).index_by(&:village_id)
        else
          {}
        end

        render json: {
          campaign: campaign&.slice(:id, :name, :election_year),
          latest_gec_list_date: latest_gec_list_date,
          current_period: current_period && {
            id: current_period.id,
            name: current_period.name,
            due_date: current_period.due_date,
            quota_target: current_period.effective_quota_target
          },
          quotas: villages.map { |village|
            quota = existing_quotas[village.id]
            current_village_quota = current_period_village_quotas[village.id]
            {
              village_id: village.id,
              village_name: village.name,
              region: village.region,
              registered_voters: village.registered_voters,
              quota_id: quota&.id,
              target_count: current_period_targets[village.id] || quota&.target_count || 0,
              period: quota&.period,
              target_date: quota&.target_date,
              updated_at: current_village_quota&.updated_at&.iso8601 || quota&.updated_at&.iso8601
            }
          }
        }
      end

      # PATCH /api/v1/quotas/:village_id
      def update
        campaign = Campaign.active.first
        return render_no_active_campaign unless campaign

        village = Village.find(params[:village_id])
        target_count = quota_params[:target_count].to_i
        if target_count <= 0
          return render_api_error(
            message: "Target count must be greater than 0",
            status: :unprocessable_entity,
            code: "invalid_quota_target"
          )
        end

        legacy_targets = Quota.where(campaign: campaign).pluck(:village_id, :target_count).to_h
        quota = Quota.find_or_initialize_by(campaign: campaign, village: village)
        original_target = quota.persisted? ? quota.target_count : legacy_targets[village.id]
        current_period = CampaignCycle.current_quota_period
        legacy_targets[village.id] = original_target if original_target.present?
        lock_historical_period_targets!(current_period, legacy_targets)
        quota.target_count = target_count
        quota.period = quota.period.presence || "quarterly"
        quota.target_date = quota.target_date.presence

        if quota.save
          sync_current_period_village_target!(village, target_count)
          changed_data = { target_count: [ original_target, quota.target_count ] }
          changed_data[:period] = [ nil, quota.period ] if original_target.nil?
          log_quota_audit!(quota, changed_data: changed_data)
          CampaignBroadcast.stats_update({
            action: "quota_updated",
            village_id: village.id,
            village_name: village.name
          })

          render json: {
            quota: {
              id: quota.id,
              village_id: village.id,
              village_name: village.name,
              target_count: quota.target_count,
              period: quota.period,
              target_date: quota.target_date,
              updated_at: quota.updated_at&.iso8601
            }
          }
        else
          render_api_error(
            message: quota.errors.full_messages.join(", "),
            status: :unprocessable_entity,
            code: "quota_update_failed"
          )
        end
      end

      private

      def quota_params
        params.require(:quota).permit(:target_count, :change_note)
      end

      def render_no_active_campaign
        render_api_error(
          message: "No active campaign found",
          status: :unprocessable_entity,
          code: "campaign_not_found"
        )
      end

      def sync_current_period_village_target!(village, target_count)
        current_period = CampaignCycle.current_quota_period
        return unless current_period

        village_quota = current_period.village_quotas.find_or_initialize_by(village: village)
        village_quota.target = target_count
        village_quota.save!
      end

      def lock_historical_period_targets!(current_period, legacy_targets)
        return unless current_period

        current_period.campaign_cycle.quota_periods
          .where("end_date < ?", current_period.start_date)
          .find_each do |period|
            legacy_targets.each do |village_id, target_count|
              next unless target_count.present?

              period.village_quotas.find_or_create_by!(village_id: village_id) do |village_quota|
                village_quota.target = target_count
              end
            end
          end
      end

      def log_quota_audit!(quota, changed_data:)
        metadata = {
          resource: "quota",
          village_id: quota.village_id
        }
        change_note = quota_params[:change_note].to_s.strip
        metadata[:change_note] = change_note if change_note.present?
        AuditLog.create!(
          auditable: quota,
          actor_user: current_user,
          action: "updated",
          changed_data: normalized_changed_data(changed_data),
          metadata: metadata
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
    end
  end
end
