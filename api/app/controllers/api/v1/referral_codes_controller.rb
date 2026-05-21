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
        scope = referral_code_scope.includes(:village, :assigned_user, :created_by_user)
        scope = apply_status_filter(scope)
        scope = apply_search_filter(scope)

        per_page = [ [ params.fetch(:per_page, 10).to_i, 1 ].max, 50 ].min
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        total = scope.count
        total_pages = total.zero? ? 1 : (total.to_f / per_page).ceil
        page = [ page, total_pages ].min
        codes = scope.order(active: :desc, created_at: :desc).offset((page - 1) * per_page).limit(per_page).to_a
        period = resolved_quota_period
        active_period = QuotaPeriod.active_for
        period_counts = referral_counts(codes, period: period)
        lifetime_counts = referral_counts(codes)

        render json: {
          referral_codes: codes.map { |code| referral_code_json(code, period_counts: period_counts, lifetime_counts: lifetime_counts) },
          signup_base_url: signup_base_url,
          active_quota_period: active_period && quota_period_summary(active_period),
          selected_quota_period: period && quota_period_summary(period),
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            pages: total_pages
          },
          filters: {
            status: status_filter,
            q: search_query,
            quota_period_id: params[:quota_period_id].presence || "all"
          }
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

        metadata = normalize_source_metadata(source_metadata(attrs))
        return unless validate_source_metadata(metadata, village)

        code = ReferralCode.new(
          display_name: attrs[:display_name].to_s.strip,
          village: village,
          assigned_user: assigned_user,
          created_by_user: current_user,
          active: true,
          metadata: metadata
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
        if metadata_update?(attrs)
          metadata = normalize_source_metadata(code.metadata.merge(source_metadata(attrs, compact_blank: false)))
          return unless validate_source_metadata(metadata, code.village)

          updates[:metadata] = metadata
        end

        if code.update(updates)
          log_audit!(code, action: "signup_link_updated", changed_data: code.saved_changes.except("updated_at"), normalize: true)
          render json: { referral_code: referral_code_json(code.reload), signup_base_url: signup_base_url }
        else
          render_api_error(message: code.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "signup_link_update_failed")
        end
      end

      # DELETE /api/v1/referral_codes/:id
      def destroy
        code = find_referral_code
        return unless code

        result = nil
        ActiveRecord::Base.transaction do
          code.lock!
          signup_count = code.supporters.count

          if signup_count.zero?
            snapshot = referral_code_json(code)
            code.destroy!
            log_audit!(code, action: "signup_link_deleted", changed_data: snapshot)
            result = { message: "Signup link deleted", deleted: true }
          else
            code.update!(active: false)
            log_audit!(code, action: "signup_link_archived", changed_data: { "active" => [ true, false ], "signup_count" => signup_count }, normalize: true)
            result = {
              message: "Signup link archived because it already has signup history",
              deleted: false,
              referral_code: referral_code_json(code.reload),
              signup_base_url: signup_base_url
            }
          end
        end

        render json: result
      end

      # GET /api/v1/referral_codes/:id/supporters
      def supporters
        code = find_referral_code
        return unless code

        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 10 ].max, 50 ].min
        supporters = code.supporters.includes(:village).order(created_at: :desc)
        total = supporters.count
        rows = supporters.offset((page - 1) * per_page).limit(per_page)

        render json: {
          supporters: rows.map { |supporter| referral_supporter_json(supporter) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            pages: (total.to_f / per_page).ceil
          }
        }
      end

      private

      def referral_code_scope
        ids = scoped_village_ids
        ids ? ReferralCode.where(village_id: ids) : ReferralCode.all
      end

      def apply_status_filter(scope)
        case status_filter
        when "inactive"
          scope.where(active: false)
        when "all"
          scope
        else
          scope.where(active: true)
        end
      end

      def apply_search_filter(scope)
        query = search_query
        return scope if query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope.where(
          "LOWER(referral_codes.display_name) LIKE :pattern OR LOWER(referral_codes.code) LIKE :pattern OR LOWER(COALESCE(referral_codes.metadata->>'notes', '')) LIKE :pattern OR LOWER(COALESCE(referral_codes.metadata->>'source_type', '')) LIKE :pattern",
          pattern: pattern
        )
      end

      def status_filter
        requested = params[:status].to_s
        %w[active inactive all].include?(requested) ? requested : "active"
      end

      def search_query
        params[:q].to_s.strip
      end

      def resolved_quota_period
        requested = params[:quota_period_id].to_s
        return QuotaPeriod.active_for if requested == "active"
        return nil if requested.blank? || requested == "all"

        QuotaPeriod.find_by(id: requested.to_i)
      end

      def referral_counts(codes, period: nil)
        ids = Array(codes).map(&:id)
        return {} if ids.empty?

        scope = Supporter.where(referral_code_id: ids)
        scope = scope.where(quota_period_id: period.id) if period
        scope.group(:referral_code_id).count
      end

      def quota_period_summary(period)
        {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date,
          status: period.status
        }
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

      def normalize_source_metadata(metadata)
        metadata["precinct_id"] = nil unless metadata["source_type"].presence == "precinct"
        metadata
      end

      def metadata_update?(attrs)
        attrs.key?(:source_type) || attrs.key?(:precinct_id) || attrs.key?(:notes)
      end

      def validate_source_metadata(metadata, village)
        return true unless metadata["source_type"].presence == "precinct"

        precinct_id = metadata["precinct_id"].presence
        unless precinct_id
          render_api_error(message: "Precinct is required for precinct signup links", status: :unprocessable_entity, code: "precinct_required")
          return false
        end

        unless village.precincts.exists?(id: precinct_id)
          render_api_error(message: "Precinct not found for village", status: :unprocessable_entity, code: "precinct_not_found")
          return false
        end

        true
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

      def referral_code_json(code, period_counts: nil, lifetime_counts: nil)
        lifetime_count = lifetime_counts ? lifetime_counts[code.id].to_i : code.supporters.count
        count = period_counts ? period_counts[code.id].to_i : lifetime_count
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
          signup_count: lifetime_count,
          period_signup_count: count,
          lifetime_signup_count: lifetime_count,
          signup_url: url,
          created_at: code.created_at&.iso8601,
          updated_at: code.updated_at&.iso8601
        }
      end

      def referral_supporter_json(supporter)
        {
          id: supporter.id,
          print_name: supporter.print_name,
          contact_number: supporter.contact_number,
          village_name: supporter.village&.name,
          source: supporter.source,
          contact_classification: supporter.contact_classification,
          created_at: supporter.created_at&.iso8601
        }
      end

      def audit_entry_mode
        "signup_links"
      end
    end
  end
end
