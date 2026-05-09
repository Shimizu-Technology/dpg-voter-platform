# frozen_string_literal: true

module Api
  module V1
    class VillagesController < ApplicationController
      include Authenticatable
      before_action :authenticate_request, only: [ :show ]
      before_action :require_supporter_access!, only: [ :show ]

      # GET /api/v1/villages (public — for signup form dropdown)
      def index
        villages = Village.includes(:precincts).order(:name)
        render json: {
          villages: villages.map { |v|
            {
              id: v.id,
              name: v.name,
              district_id: v.district_id,
              district_name: v.district&.name,
              region: v.region,
              registered_voters: v.registered_voters,
              precincts: v.precincts.order(:number).map { |p|
                { id: p.id, number: p.number, alpha_range: p.alpha_range }
              }
            }
          }
        }
      end

      # GET /api/v1/villages/:id
      def show
        scoped_villages = scoped_village_ids.nil? ? Village.all : Village.where(id: scoped_village_ids)
        village = scoped_villages.includes(:precincts, :blocks).find_by(id: params[:id])
        unless village
          return render_api_error(
            message: "Not authorized for this village",
            status: :forbidden,
            code: "village_access_required"
          )
        end
        official_supporters_count = village.supporters.official_supporters.count
        matched_to_gec_count = village.supporters.official_supporters.verified.count
        total_count = village.supporters.active.count
        team_pending_count = village.supporters.pending_supporter_review.where(source: Supporter::TEAM_SOURCES).count
        public_pending_count = village.supporters.active.public_signups.count
        precinct_supporter_counts = village.supporters.official_supporters.where.not(precinct_id: nil).group(:precinct_id).count
        unassigned_precinct_count = village.supporters.official_supporters.where(precinct_id: nil).count
        latest_gec_list_date = GecVoter.active.maximum(:gec_list_date)
        pending_review_count = team_pending_count + public_pending_count

        render json: {
          village: {
            id: village.id,
            name: village.name,
            region: village.region,
            registered_voters: village.registered_voters,
            official_supporters_count: official_supporters_count,
            matched_to_gec_count: matched_to_gec_count,
            team_approved_count: village.supporters.team_input.count,
            public_approved_count: village.supporters.official_supporters.public_origin.count,
            team_pending_count: team_pending_count,
            public_pending_count: public_pending_count,
            latest_gec_list_date: latest_gec_list_date,
            # Legacy compat
            verified_count: matched_to_gec_count,
            total_count: total_count,
            unverified_count: pending_review_count,
            supporter_count: official_supporters_count,
            precincts: village.precincts.order(:number).map { |p|
              {
                id: p.id,
                number: p.number,
                alpha_range: p.alpha_range,
                registered_voters: p.registered_voters,
                polling_site: p.polling_site,
                supporter_count: precinct_supporter_counts[p.id] || 0
              }
            },
            unassigned_precinct_count: unassigned_precinct_count,
            blocks: village.blocks.order(:name).map { |b|
              {
                id: b.id,
                name: b.name,
                verified_count: b.supporters.official_supporters.verified.count,
                total_count: b.supporters.active.count,
                supporter_count: b.supporters.official_supporters.count
              }
            }
          }
        }
      end

      private
    end
  end
end
