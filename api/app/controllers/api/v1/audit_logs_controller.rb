# frozen_string_literal: true

module Api
  module V1
    class AuditLogsController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_audit_logs_access!

      MAX_PER_PAGE = 100

      # GET /api/v1/audit_logs
      def index
        logs = AuditLog.includes(:actor_user).recent
        logs = apply_filters(logs)

        page = [ params[:page].to_i, 1 ].max
        per_page = (params[:per_page] || 50).to_i.clamp(1, MAX_PER_PAGE)

        total = logs.select("audit_logs.id").distinct.count
        paginated_logs = logs.offset((page - 1) * per_page).limit(per_page)

        render json: {
          audit_logs: serialize_logs(paginated_logs),
          filters: page <= 1 ? cached_filter_options : nil,
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            pages: (total.to_f / per_page).ceil
          }
        }
      end

      private

      def cached_filter_options
        Rails.cache.fetch("audit_log_filter_options", expires_in: 5.minutes) do
          {
            actions: AuditLog.distinct.order(:action).pluck(:action),
            auditable_types: AuditLog.distinct.order(:auditable_type).pluck(:auditable_type).compact
          }
        end
      end

      def apply_filters(scope)
        scope = scope.where(action: params[:audit_action]) if params[:audit_action].present?
        scope = scope.where(actor_user_id: params[:actor_user_id]) if params[:actor_user_id].present?
        scope = scope.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?

        if params[:q].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
          query = "%#{sanitized.downcase}%"
          scope = scope.left_joins(:actor_user).where(
            "LOWER(audit_logs.action) LIKE :q OR LOWER(COALESCE(users.name, '')) LIKE :q OR LOWER(COALESCE(users.email, '')) LIKE :q OR LOWER(audit_logs.auditable_type) LIKE :q",
            q: query
          )
        end

        scope
      end

      def serialize_logs(logs)
        supporter_ids = logs.select { |log| log.auditable_type == "Supporter" }.map(&:auditable_id).compact.uniq
        user_ids = logs.select { |log| log.auditable_type == "User" }.map(&:auditable_id).compact.uniq

        supporters_by_id = Supporter.where(id: supporter_ids).index_by(&:id)
        users_by_id = User.where(id: user_ids).index_by(&:id)

        logs.map do |log|
          {
            id: log.id,
            action: log.action,
            action_label: log.action.to_s.humanize,
            auditable_type: log.auditable_type,
            auditable_id: log.auditable_id,
            auditable_label: auditable_label_for(log, supporters_by_id: supporters_by_id, users_by_id: users_by_id),
            actor_user_id: log.actor_user_id,
            actor_name: log.actor_user&.name,
            actor_email: log.actor_user&.email,
            actor_role: log.actor_user&.role,
            changed_data: log.changed_data || {},
            metadata: log.metadata || {},
            created_at: log.created_at&.iso8601
          }
        end
      end

      def auditable_label_for(log, supporters_by_id:, users_by_id:)
        case log.auditable_type
        when "Supporter"
          supporters_by_id[log.auditable_id]&.display_name || "Supporter ##{log.auditable_id}"
        when "User"
          user = users_by_id[log.auditable_id]
          user&.name.presence || user&.email.presence || "User ##{log.auditable_id}"
        else
          "#{log.auditable_type} ##{log.auditable_id}"
        end
      end
    end
  end
end
