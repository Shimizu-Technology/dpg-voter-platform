# frozen_string_literal: true

module Api
  module V1
    class StaffSupportersController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_staff_entry_access!

      # POST /api/v1/staff/supporters (authenticated staff entry)
      def create
        # Enforce village scope for non-admin users
        village_id = staff_supporter_params[:village_id]
        if village_id.present? && scoped_village_ids && !scoped_village_ids.include?(village_id.to_i)
          return render json: { errors: [ "Village not in your assigned scope" ] }, status: :forbidden
        end

        supporter = Supporter.new(staff_supporter_params)
        supporter.source = "staff_entry"
        supporter.attribution_method = "staff_manual"
        supporter.status = "active"
        supporter.entered_by_user_id = current_user.id

        # Check for duplicates
        dupes = Supporter.potential_duplicates(supporter.print_name, supporter.village_id, first_name: supporter.first_name, last_name: supporter.last_name)
        if dupes.exists? && params[:force] != "true"
          return render json: {
            duplicate_warning: true,
            message: "Possible duplicate found. Submit with force=true to override.",
            duplicates: dupes.map { |s| { id: s.id, first_name: s.first_name, last_name: s.last_name, print_name: s.print_name, contact_number: s.contact_number, village: s.village&.name } }
          }, status: :conflict
        end

        if supporter.save
          log_audit!(supporter, action: "created", changed_data: supporter.saved_changes.except("updated_at"), normalize: true)
          render json: { supporter: supporter_json(supporter) }, status: :created
        else
          render json: { errors: supporter.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def staff_supporter_params
        params.require(:supporter).permit(
          :first_name, :middle_name, :last_name, :print_name, :contact_number, :dob, :email, :street_address,
          :village_id, :precinct_id, :block_id,
          :registered_voter,
          :opt_in_email, :opt_in_text
        )
      end

      def supporter_json(supporter)
        {
          id: supporter.id,
          first_name: supporter.first_name,
          middle_name: supporter.middle_name,
          last_name: supporter.last_name,
          print_name: supporter.print_name,
          contact_number: supporter.contact_number,
          village_name: supporter.village&.name,
          opt_in_email: supporter.opt_in_email,
          opt_in_text: supporter.opt_in_text,
          source: supporter.source,
          status: supporter.status,
          created_at: supporter.created_at&.iso8601
        }
      end

      def audit_entry_mode
        "staff_manual_api"
      end
    end
  end
end
