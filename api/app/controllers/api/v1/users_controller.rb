# frozen_string_literal: true

require "digest"

module Api
  module V1
    class UsersController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_user_manager!

      # GET /api/v1/users
      def index
        users = if current_user.admin?
          User.all
        else
          User.where(role: manageable_roles_for_current_user)
        end.includes(poll_watcher_precinct_assignments: { precinct: :village }).order(:role, :name, :email)

        render json: {
          users: users.map { |u| user_json(u) },
          roles: manageable_roles_for_current_user
        }
      end

      # POST /api/v1/users
      def create
        email = user_create_params[:email].to_s.strip.downcase
        role = user_create_params[:role]
        unless manageable_roles_for_current_user.include?(role)
          return render_api_error(
            message: "You do not have permission to assign role: #{role}",
            status: :forbidden,
            code: "user_role_assignment_forbidden"
          )
        end

        user = User.find_or_initialize_by(email: email)
        user.clerk_id = placeholder_clerk_id(email) if user.clerk_id.blank?
        user.role = role if role.present?
        user.assigned_district_id = user_create_params[:assigned_district_id] if user_create_params.key?(:assigned_district_id)
        user.assigned_village_id = user_create_params[:assigned_village_id] if user_create_params.key?(:assigned_village_id)
        user.assigned_block_id = user_create_params[:assigned_block_id] if user_create_params.key?(:assigned_block_id)

        assignment_ids = requested_poll_watcher_precinct_ids
        return unless valid_poll_watcher_assignment?(role: user.role, precinct_ids: assignment_ids)

        User.transaction do
          user.save!
          sync_poll_watcher_assignments!(user, assignment_ids)
        end

        if user.persisted?
          SendUserInviteEmailJob.perform_later(user.id, current_user&.id)
          render json: { user: user_json(user) }, status: :created
        end
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(
          message: e.record.errors.full_messages.join(", "),
          status: :unprocessable_entity,
          code: "user_create_failed"
        )
      rescue ActiveRecord::RecordNotFound
        render_api_error(
          message: "One or more selected precincts are unavailable",
          status: :unprocessable_entity,
          code: "poll_watcher_precinct_invalid"
        )
      end

      # PATCH /api/v1/users/:id
      def update
        user = User.find(params[:id])
        unless manageable_roles_for_current_user.include?(user.role)
          return render_api_error(
            message: "You do not have permission to edit this user",
            status: :forbidden,
            code: "user_edit_forbidden"
          )
        end

        updates = user_update_params.to_h.except("poll_watcher_precinct_ids")

        if updates["email"].present?
          updates["email"] = updates["email"].to_s.strip.downcase
        end

        if updates["role"].present? && !manageable_roles_for_current_user.include?(updates["role"])
          return render_api_error(
            message: "You do not have permission to assign role: #{updates["role"]}",
            status: :forbidden,
            code: "user_role_assignment_forbidden"
          )
        end

        resulting_role = updates["role"].presence || user.role
        assignment_ids = requested_poll_watcher_precinct_ids
        return unless valid_poll_watcher_assignment?(role: resulting_role, precinct_ids: assignment_ids)

        User.transaction do
          user.update!(updates)
          sync_poll_watcher_assignments!(user, assignment_ids)
        end

        if user.persisted?
          render json: { user: user_json(user) }
        end
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(
          message: e.record.errors.full_messages.join(", "),
          status: :unprocessable_entity,
          code: "user_update_failed"
        )
      rescue ActiveRecord::RecordNotFound
        render_api_error(
          message: "One or more selected precincts are unavailable",
          status: :unprocessable_entity,
          code: "poll_watcher_precinct_invalid"
        )
      end

      # DELETE /api/v1/users/:id
      def destroy
        user = User.find(params[:id])

        if user.id == current_user.id
          return render_api_error(
            message: "You cannot remove yourself",
            status: :unprocessable_entity,
            code: "user_self_delete"
          )
        end

        unless manageable_roles_for_current_user.include?(user.role)
          return render_api_error(
            message: "You do not have permission to remove this user",
            status: :forbidden,
            code: "user_delete_forbidden"
          )
        end

        begin
          user.destroy!
        rescue ActiveRecord::DeleteRestrictionError
          return render_api_error(
            message: "Cannot remove this user because they have associated activity records. Reassign or clear their activity first.",
            status: :unprocessable_entity,
            code: "user_has_dependencies"
          )
        rescue ActiveRecord::InvalidForeignKey => e
          return render_api_error(
            message: foreign_key_dependency_message(e),
            status: :unprocessable_entity,
            code: "user_has_dependencies"
          )
        end
        render json: { message: "User removed" }, status: :ok
      end

      # POST /api/v1/users/:id/resend_invite
      def resend_invite
        user = User.find(params[:id])
        unless manageable_roles_for_current_user.include?(user.role)
          return render_api_error(
            message: "You do not have permission to resend invite for this user",
            status: :forbidden,
            code: "user_resend_invite_forbidden"
          )
        end

        if user.email.blank?
          return render_api_error(
            message: "User does not have an email address",
            status: :unprocessable_entity,
            code: "user_email_required"
          )
        end

        SendUserInviteEmailJob.perform_later(user.id, current_user&.id)
        render json: { message: "Invite email queued", user: user_json(user) }, status: :accepted
      end

      private

      def user_create_params
        params.require(:user).permit(
          :email, :role,
          :assigned_district_id, :assigned_village_id, :assigned_block_id,
          poll_watcher_precinct_ids: []
        )
      end

      def user_update_params
        params.require(:user).permit(
          :email, :name, :role, :phone,
          :assigned_district_id, :assigned_village_id, :assigned_block_id,
          poll_watcher_precinct_ids: []
        )
      end

      def placeholder_clerk_id(email)
        "pending-#{Digest::SHA256.hexdigest(email).first(24)}"
      end

      def foreign_key_dependency_message(error)
        table_name = error.message.scan(/table "([^"]+)"/).flatten.last
        base_message = "Cannot remove this user because they still have associated records."
        return base_message if table_name.blank?

        "#{base_message} Clear or reassign their #{table_name.humanize.downcase} first."
      end

      def user_json(user)
        assignments = user.poll_watcher_precinct_assignments.sort_by do |assignment|
          [ assignment.precinct.village.name, assignment.precinct.number ]
        end
        {
          id: user.id,
          email: user.email,
          name: user.name,
          phone: user.phone,
          role: user.role,
          assigned_district_id: user.assigned_district_id,
          assigned_village_id: user.assigned_village_id,
          assigned_block_id: user.assigned_block_id,
          poll_watcher_precinct_ids: assignments.map(&:precinct_id),
          poll_watcher_precincts: assignments.map do |assignment|
            {
              id: assignment.precinct_id,
              number: assignment.precinct.number,
              village_name: assignment.precinct.village.name
            }
          end,
          created_at: user.created_at&.iso8601
        }
      end

      def requested_poll_watcher_precinct_ids
        Array(params.dig(:user, :poll_watcher_precinct_ids)).filter_map do |value|
          Integer(value, exception: false)
        end.uniq
      end

      def valid_poll_watcher_assignment?(role:, precinct_ids:)
        return true unless role == "poll_watcher"

        if precinct_ids.empty?
          render_api_error(
            message: "Assign at least one precinct to a poll watcher",
            status: :unprocessable_entity,
            code: "poll_watcher_precinct_required"
          )
          return false
        end

        allowed_ids = allowed_poll_watcher_precinct_scope.where(id: precinct_ids).pluck(:id)
        return true if allowed_ids.sort == precinct_ids.sort

        render_api_error(
          message: "You cannot assign one or more of the selected precincts",
          status: :forbidden,
          code: "poll_watcher_precinct_forbidden"
        )
        false
      end

      def allowed_poll_watcher_precinct_scope
        ids = scoped_village_ids
        ids.nil? ? Precinct.active : Precinct.active.where(village_id: ids)
      end

      def sync_poll_watcher_assignments!(user, precinct_ids)
        unless user.poll_watcher?
          user.poll_watcher_precinct_assignments.destroy_all
          return
        end

        user.update!(assigned_village_id: nil, assigned_district_id: nil, assigned_block_id: nil)
        user.poll_watcher_precinct_assignments.where.not(precinct_id: precinct_ids).destroy_all
        existing_ids = user.poll_watcher_precinct_assignments.where(precinct_id: precinct_ids).pluck(:precinct_id)
        (precinct_ids - existing_ids).each do |precinct_id|
          user.poll_watcher_precinct_assignments.create!(
            precinct: allowed_poll_watcher_precinct_scope.find(precinct_id),
            assigned_by_user: current_user
          )
        end
        user.association(:poll_watcher_precinct_assignments).reset
      end
    end
  end
end
