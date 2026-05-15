# frozen_string_literal: true

module Api
  module V1
    class SessionController < ApplicationController
      include Authenticatable
      before_action :authenticate_request

      # GET /api/v1/session
      def show
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
        response.headers["Pragma"] = "no-cache"

        contact_scope = scope_supporters(Supporter.contacts)
        intake_scope = scope_supporters(Supporter.intake)
        official_scope = scope_supporters(Supporter.official_supporters)
        matched_scope = contact_scope.verified

        render json: {
          user: {
            id: current_user.id,
            email: current_user.email,
            name: current_user.name,
            role: current_user.role,
            assigned_village_id: current_user.assigned_village_id,
            assigned_district_id: current_user.assigned_district_id,
            assigned_block_id: current_user.assigned_block_id,
            scoped_village_ids: scoped_village_ids
          },
          counts: {
            total_contacts: contact_scope.count,
            new_intake: intake_scope.count,
            supporters: scope_supporters(Supporter.classified_supporters).count,
            members: scope_supporters(Supporter.members).count,
            volunteers: scope_supporters(Supporter.volunteers).count,
            needs_follow_up: contact_scope.needs_follow_up.count,
            matched_to_gec: matched_scope.count,
            pending_vetting: intake_scope.count,
            flagged_supporters: contact_scope.flagged.count,
            public_signups_pending: intake_scope.public_origin.count,
            official_supporters: official_scope.count
          },
          permissions: {
            can_manage_users: can_manage_users?,
            can_manage_configuration: can_manage_configuration?,
            can_manage_data_configuration: can_manage_data_configuration?,
            can_send_sms: can_send_sms?,
            can_send_email: can_send_email?,
            can_edit_supporters: can_edit_supporters?,
            can_view_supporters: can_view_supporters?,
            can_create_staff_supporters: can_create_staff_supporters?,
            can_access_duplicates: can_access_duplicates?,
            can_access_audit_logs: can_access_audit_logs?,
            can_access_data_team: can_access_data_team?,
            can_access_reports: can_access_reports?,
            can_access_qr: can_access_qr?,
            can_import_supporters: can_import_supporters?,
            can_upload_gec: can_upload_gec?,
            can_bulk_vet: can_bulk_vet?,
            can_review_public: can_review_public?,
            default_route: "/admin",
            manageable_roles: manageable_roles_for_current_user
          }
        }
      end

      private
    end
  end
end
