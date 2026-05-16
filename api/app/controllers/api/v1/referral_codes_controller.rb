# frozen_string_literal: true

require "cgi"

module Api
  module V1
    class ReferralCodesController < ApplicationController
      include Authenticatable
      include AuditLoggable

      before_action :authenticate_request
      before_action :require_qr_access!

      # GET /api/v1/referral_codes
      def index
        codes = referral_code_scope
          .includes(:village, :assigned_user, :created_by_user)
          .left_joins(:supporters)
          .select("referral_codes.*, COUNT(supporters.id) AS supporters_count")
          .group("referral_codes.id")
          .order(active: :desc, created_at: :desc)

        render json: {
          referral_codes: codes.map { |code| referral_code_json(code) },
          signup_base_url: signup_base_url
        }
      end

      # POST /api/v1/referral_codes
      def create
        attrs = create_referral_code_params
        village = Village.find_by(id: attrs[:village_id])
        unless village
          return render_api_error(message: "Village not found", status: :not_found, code: "village_not_found")
        end

        unless village_allowed?(village.id)
          return render_api_error(message: "Village not in your assigned scope", status: :forbidden, code: "village_scope_required")
        end

        assigned_user = resolve_assigned_user(attrs[:assigned_user_id])
        return if performed?

        code = ReferralCode.new(
          display_name: attrs[:display_name].to_s.strip,
          village: village,
          assigned_user: assigned_user,
          created_by_user: current_user,
          active: true,
          metadata: source_metadata(attrs)
        )
        code.code = ReferralCode.generate_unique_code(display_name: code.display_name, village_name: village.name)

        if code.save
          log_audit!(code, action: "signup_link_created", changed_data: referral_code_json(code))
          render json: { referral_code: referral_code_json(code), signup_base_url: signup_base_url }, status: :created
        else
          render_api_error(message: code.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "signup_link_create_failed")
        end
      end

      # PATCH /api/v1/referral_codes/:id
      def update
        code = find_referral_code
        return unless code

        attrs = update_referral_code_params
        updates = {}
        updates[:display_name] = attrs[:display_name].to_s.strip if attrs.key?(:display_name)
        updates[:active] = ActiveModel::Type::Boolean.new.cast(attrs[:active]) if attrs.key?(:active)
        updates[:metadata] = code.metadata.merge(source_metadata(attrs, compact_blank: false)) if metadata_update?(attrs)

        if code.update(updates)
          log_audit!(code, action: "signup_link_updated", changed_data: code.saved_changes.except("updated_at"), normalize: true)
          render json: { referral_code: referral_code_json(code.reload), signup_base_url: signup_base_url }
        else
          render_api_error(message: code.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "signup_link_update_failed")
        end
      end

      private

      def referral_code_scope
        ids = scoped_village_ids
        ids ? ReferralCode.where(village_id: ids) : ReferralCode.all
      end

      def find_referral_code
        code = referral_code_scope.find_by(id: params[:id])
        unless code
          render_api_error(message: "Signup link not found", status: :not_found, code: "referral_code_not_found")
        end

        code
      end

      def create_referral_code_params
        params.require(:referral_code).permit(:display_name, :village_id, :assigned_user_id, :source_type, :precinct_id, :notes, :active)
      end

      def update_referral_code_params
        params.require(:referral_code).permit(:display_name, :source_type, :precinct_id, :notes, :active)
      end

      def source_metadata(attrs, compact_blank: true)
        metadata = {}
        metadata["source_type"] = attrs[:source_type].presence || "custom" if attrs.key?(:source_type)
        metadata["precinct_id"] = attrs[:precinct_id].presence if attrs.key?(:precinct_id)
        metadata["notes"] = attrs[:notes].presence if attrs.key?(:notes)
        compact_blank ? metadata.compact : metadata
      end

      def metadata_update?(attrs)
        attrs.key?(:source_type) || attrs.key?(:precinct_id) || attrs.key?(:notes)
      end

      def resolve_assigned_user(user_id)
        return nil if user_id.blank?

        user = User.find_by(id: user_id)
        unless user
          render_api_error(message: "Assigned user not found", status: :not_found, code: "user_not_found")
          return nil
        end

        if scoped_village_ids && user.assigned_village_id.present? && !scoped_village_ids.include?(user.assigned_village_id)
          render_api_error(message: "Assigned user is outside your village scope", status: :forbidden, code: "user_scope_required")
          return nil
        end

        user
      end

      def village_allowed?(village_id)
        scoped_village_ids.nil? || scoped_village_ids.include?(village_id)
      end

      def signup_base_url
        ENV["FRONTEND_URL"].presence || "http://localhost:5173"
      end

      def referral_code_json(code)
        count = code.respond_to?(:supporters_count) ? code.supporters_count.to_i : code.supporters.count
        url = "#{signup_base_url.to_s.delete_suffix('/')}/signup/#{CGI.escape(code.code)}"
        {
          id: code.id,
          code: code.code,
          display_name: code.display_name,
          active: code.active,
          village_id: code.village_id,
          village_name: code.village&.name,
          assigned_user_id: code.assigned_user_id,
          assigned_user_name: code.assigned_user&.name,
          created_by_user_id: code.created_by_user_id,
          created_by_user_name: code.created_by_user&.name,
          source_type: code.source_type,
          precinct_id: code.precinct_id,
          notes: code.notes,
          signup_count: count,
          signup_url: url,
          created_at: code.created_at&.iso8601,
          updated_at: code.updated_at&.iso8601
        }
      end

      def audit_entry_mode
        "signup_links"
      end
    end
  end
end
