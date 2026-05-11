# frozen_string_literal: true

module Api
  module V1
    class DistrictsController < ApplicationController
      include Authenticatable

      before_action :authenticate_request
      before_action :load_supporter_counts, only: [ :index, :create, :update, :assign_villages ]
      before_action :require_admin!, only: [ :create, :update, :destroy, :assign_villages ]

      # GET /api/v1/districts
      def index
        districts = District.includes(:villages).order(:name)
        unassigned_villages = Village.where(district_id: nil).order(:name)

        render json: {
          districts: districts.map { |d| district_json(d) },
          unassigned_villages: unassigned_villages.map { |v| village_summary(v) }
        }
      end

      # POST /api/v1/districts
      def create
        campaign = Campaign.active.first
        unless campaign
          return render_api_error(message: "No active campaign", status: :unprocessable_entity)
        end

        district = District.new(district_params.merge(campaign_id: campaign.id))
        if district.save
          render json: { district: district_json(district) }, status: :created
        else
          render_api_error(
            message: district.errors.full_messages.join(", "),
            status: :unprocessable_entity
          )
        end
      end

      # PATCH /api/v1/districts/:id
      def update
        district = District.find(params[:id])
        if district.update(district_params)
          render json: { district: district_json(district) }
        else
          render_api_error(
            message: district.errors.full_messages.join(", "),
            status: :unprocessable_entity
          )
        end
      end

      # DELETE /api/v1/districts/:id
      def destroy
        district = District.find(params[:id])
        # Clear assignment for any users assigned to this district
        User.where(assigned_district_id: district.id).update_all(assigned_district_id: nil)
        # Explicitly nullify village associations before destroy (don't rely on DB cascade)
        district.villages.update_all(district_id: nil)
        district.destroy!
        render json: { message: "District deleted" }
      end

      # PATCH /api/v1/districts/:id/assign_villages
      def assign_villages
        district = District.find(params[:id])
        village_ids = Array(params[:village_ids]).map(&:to_i)

        # Remove villages currently in this district that aren't in the new list
        district.villages.where.not(id: village_ids).update_all(district_id: nil)

        # Check for villages already assigned to other districts
        if village_ids.any?
          conflicting = Village.where(id: village_ids).where.not(district_id: [ nil, district.id ])
          if conflicting.any?
            return render json: {
              error: "Villages already assigned to other districts: #{conflicting.pluck(:name).join(', ')}. Remove them first.",
              conflicting_villages: conflicting.pluck(:name)
            }, status: :unprocessable_entity
          end

          Village.where(id: village_ids).update_all(district_id: district.id)
        end

        district.reload
        render json: { district: district_json(district) }
      end

      private

      def district_params
        params.require(:district).permit(:name, :description)
      end

      # Batch load supporter counts to avoid N+1 queries
      def load_supporter_counts
        @official_counts = Supporter.official_supporters.group(:village_id).count
        @matched_counts = Supporter.contacts.verified.group(:village_id).count
        @total_counts = Supporter.contacts.group(:village_id).count
        @registered_voter_counts = Precinct.group(:village_id).sum(:registered_voters)
      end

      def district_json(district)
        {
          id: district.id,
          name: district.name,
          description: district.description,
          villages: district.villages.sort_by(&:name).map { |v| village_summary(v) },
          official_count: district.village_ids.sum { |vid| @official_counts.fetch(vid, 0) },
          matched_count: district.village_ids.sum { |vid| @matched_counts.fetch(vid, 0) },
          verified_count: district.village_ids.sum { |vid| @matched_counts.fetch(vid, 0) },
          total_count: district.village_ids.sum { |vid| @total_counts.fetch(vid, 0) },
          supporter_count: district.village_ids.sum { |vid| @official_counts.fetch(vid, 0) },
          registered_voters: district.village_ids.sum { |vid| @registered_voter_counts.fetch(vid, 0) }
        }
      end

      def village_summary(village)
        {
          id: village.id,
          name: village.name,
          official_count: @official_counts.fetch(village.id, 0),
          matched_count: @matched_counts.fetch(village.id, 0),
          verified_count: @matched_counts.fetch(village.id, 0),
          total_count: @total_counts.fetch(village.id, 0),
          supporter_count: @official_counts.fetch(village.id, 0),
          registered_voters: @registered_voter_counts.fetch(village.id, 0)
        }
      end
    end
  end
end
