# frozen_string_literal: true

require "rqrcode"

module Api
  module V1
    class QrCodesController < ApplicationController
      include Authenticatable
      before_action :authenticate_request, only: [ :generate, :assignees ]
      before_action :require_qr_access!, only: [ :generate, :assignees ]

      # GET /api/v1/qr_codes/:code (public — QR images need to be accessible)
      # Returns a QR code SVG for the given leader code
      def show
        code = params[:id]
        base_url = ENV.fetch("FRONTEND_URL", "http://localhost:5175")
        signup_url = "#{base_url}/signup/#{code}"

        qr = RQRCode::QRCode.new(signup_url)
        svg = qr.as_svg(
          color: "1B3A6B",
          shape_rendering: "crispEdges",
          module_size: 6,
          standalone: true,
          use_path: true
        )

        render plain: svg, content_type: "image/svg+xml"
      end

      # GET /api/v1/qr_codes/:code/info
      def info
        code = params[:id]
        base_url = ENV.fetch("FRONTEND_URL", "http://localhost:5175")
        signup_url = "#{base_url}/signup/#{code}"
        signups = Supporter.active.where(leader_code: code).count

        render json: {
          code: code,
          signup_url: signup_url,
          signups_count: signups
        }
      end

      # GET /api/v1/qr_codes/assignees
      def assignees
        users = qr_assignable_users
        render json: {
          users: users.map do |user|
            {
              id: user.id,
              name: user.name,
              email: user.email,
              role: user.role,
              assigned_village_id: user.assigned_village_id,
              assigned_district_id: user.assigned_district_id
            }
          end
        }
      end

      # POST /api/v1/qr_codes/generate
      # Generate and persist a unique referral code.
      def generate
        village = resolve_village
        return if performed?

        assigned_user = resolve_assigned_user
        return if performed?
        validate_assignee_village_scope!(assigned_user, village)
        return if performed?

        display_name = resolve_display_name(assigned_user)
        if display_name.blank?
          return render_api_error(
            message: "Display name is required",
            status: :unprocessable_entity,
            code: "display_name_required"
          )
        end

        code = ReferralCode.generate_unique_code(display_name: display_name, village_name: village.name)
        referral_code = ReferralCode.create!(
          code: code,
          display_name: display_name,
          village_id: village.id,
          assigned_user: assigned_user,
          created_by_user: current_user,
          active: true
        )

        base_url = ENV.fetch("FRONTEND_URL", "http://localhost:5175")
        signup_url = "#{base_url}/signup/#{code}"

        render json: {
          code: code,
          signup_url: signup_url,
          qr_svg_url: "/api/v1/qr_codes/#{code}",
          referral_code: referral_code_json(referral_code)
        }
      end

      private

      def resolve_village
        village_id = params[:village_id].presence
        scoped_villages = scoped_village_ids.nil? ? Village.all : Village.where(id: scoped_village_ids)

        village = if village_id.present?
          scoped_villages.find_by(id: village_id)
        elsif params[:village].present?
          scoped_villages.find_by(name: params[:village].to_s)
        end

        return village if village

        render_api_error(
          message: "Village is required and must be within your accessible scope",
          status: :unprocessable_entity,
          code: "invalid_village"
        )
        nil
      end

      def resolve_assigned_user
        return nil if params[:assigned_user_id].blank?

        user = qr_assignable_users.find_by(id: params[:assigned_user_id])
        return user if user

        render_api_error(
          message: "Assigned user is not valid for your scope",
          status: :forbidden,
          code: "invalid_assigned_user"
        )
        nil
      end

      def resolve_display_name(assigned_user)
        return params[:display_name].to_s.strip if params[:display_name].present?
        return params[:name].to_s.strip if params[:name].present?
        return assigned_user.name.presence || assigned_user.email if assigned_user

        ""
      end

      def qr_assignable_users
        scope = User.where(role: %w[campaign_admin district_coordinator village_chief block_leader]).order(:role, :name, :email)
        ids = scoped_village_ids
        return scope if ids.nil?

        district_ids = Village.where(id: ids).where.not(district_id: nil).distinct.pluck(:district_id)
        scope.where(assigned_village_id: ids)
             .or(scope.where(assigned_district_id: district_ids))
             .or(scope.where(role: "campaign_admin"))
      end

      def referral_code_json(referral_code)
        {
          id: referral_code.id,
          code: referral_code.code,
          display_name: referral_code.display_name,
          village_id: referral_code.village_id,
          village_name: referral_code.village&.name,
          assigned_user_id: referral_code.assigned_user_id,
          assigned_user_name: referral_code.assigned_user&.name,
          assigned_user_email: referral_code.assigned_user&.email
        }
      end

      def validate_assignee_village_scope!(assigned_user, village)
        return if assigned_user.nil?
        return if assigned_user.admin?

        if assigned_user.coordinator? && assigned_user.assigned_district_id.present?
          district_match = Village.where(id: village.id, district_id: assigned_user.assigned_district_id).exists?
          return if district_match

          return render_api_error(
            message: "Assigned coordinator is not scoped to the selected village",
            status: :unprocessable_entity,
            code: "assigned_user_village_mismatch"
          )
        end

        if assigned_user.assigned_village_id.present? && assigned_user.assigned_village_id != village.id
          render_api_error(
            message: "Assigned user is not scoped to the selected village",
            status: :unprocessable_entity,
            code: "assigned_user_village_mismatch"
          )
        end
      end
    end
  end
end
