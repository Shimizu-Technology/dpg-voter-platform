# frozen_string_literal: true

module Api
  module V1
    class PrecinctsController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_coordinator_or_above!

      # GET /api/v1/precincts
      def index
        scope = Precinct.includes(:village).order("villages.name ASC", "precincts.number ASC").joins(:village)
        scope = scope.where(village_id: scoped_village_ids) if scoped_village_ids
        scope = scope.where(village_id: params[:village_id]) if params[:village_id].present?
        if params[:search].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)
          q = "%#{sanitized.downcase}%"
          scope = scope.where(
            "LOWER(precincts.number) LIKE :q OR LOWER(precincts.alpha_range) LIKE :q OR LOWER(precincts.polling_site) LIKE :q OR LOWER(villages.name) LIKE :q",
            q: q
          )
        end
        if params[:status].present?
          active = params[:status] == "active"
          scope = scope.where(active: active)
        end

        supporter_counts = Supporter.active.where(precinct_id: scope.map(&:id)).group(:precinct_id).count
        render json: {
          precincts: scope.map { |precinct|
            {
              id: precinct.id,
              number: precinct.number,
              alpha_range: precinct.alpha_range,
              polling_site: precinct.polling_site,
              registered_voters: precinct.registered_voters,
              active: precinct.active,
              village_id: precinct.village_id,
              village_name: precinct.village.name,
              linked_supporters_count: supporter_counts[precinct.id] || 0,
              updated_at: precinct.updated_at&.iso8601
            }
          }
        }
      end

      # PATCH /api/v1/precincts/:id
      def update
        precinct_scope = scoped_village_ids.nil? ? Precinct.all : Precinct.where(village_id: scoped_village_ids)
        precinct = precinct_scope.find_by(id: params[:id])
        unless precinct
          return render_api_error(
            message: "Not authorized for this precinct",
            status: :forbidden,
            code: "precinct_access_required"
          )
        end
        if precinct_params.key?(:registered_voters) && precinct_params[:registered_voters].to_i <= 0
          return render_api_error(
            message: "Registered voters must be greater than 0",
            status: :unprocessable_entity,
            code: "invalid_registered_voters"
          )
        end
        if turning_inactive?(precinct) && precinct.supporters.active.exists?
          return render_api_error(
            message: "Cannot deactivate precinct while supporters are assigned",
            status: :unprocessable_entity,
            code: "precinct_in_use"
          )
        end

        if precinct.update(precinct_update_params)
          changed = precinct.saved_changes.except("updated_at")
          log_precinct_audit!(precinct, changed_data: changed) if changed.present?
          render json: {
            precinct: {
              id: precinct.id,
              number: precinct.number,
              alpha_range: precinct.alpha_range,
              polling_site: precinct.polling_site,
              registered_voters: precinct.registered_voters,
              active: precinct.active,
              village_id: precinct.village_id,
              village_name: precinct.village.name,
              updated_at: precinct.updated_at&.iso8601
            }
          }
        else
          render_api_error(
            message: precinct.errors.full_messages.join(", "),
            status: :unprocessable_entity,
            code: "precinct_update_failed"
          )
        end
      end

      private

      def precinct_params
        params.require(:precinct).permit(:number, :alpha_range, :polling_site, :registered_voters, :active, :change_note)
      end

      def precinct_update_params
        precinct_params.to_h.except("change_note")
      end

      def turning_inactive?(precinct)
        return false unless precinct_params.key?(:active)

        requested_active = ActiveModel::Type::Boolean.new.cast(precinct_params[:active])
        precinct.active && !requested_active
      end

      def log_precinct_audit!(precinct, changed_data:)
        metadata = {
          resource: "precinct",
          village_id: precinct.village_id
        }
        change_note = precinct_params[:change_note].to_s.strip
        metadata[:change_note] = change_note if change_note.present?
        AuditLog.create!(
          auditable: precinct,
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
