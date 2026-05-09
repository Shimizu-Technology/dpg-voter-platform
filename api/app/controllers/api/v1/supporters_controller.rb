# frozen_string_literal: true

require "csv"

module Api
  module V1
    class SupportersController < ApplicationController
      MAX_PER_PAGE = 200
      MAX_EXPORT_ROWS = 10_000
      MAX_HOUSEHOLD_MEMBERS = 8
      ALLOWED_SORT_FIELDS = %w[created_at print_name last_name first_name village_name precinct_number source registered_voter].freeze

      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request, only: [ :index, :check_duplicate, :export, :show, :update, :verify, :bulk_verify, :revet, :bulk_revet, :duplicates, :resolve_duplicate, :scan_duplicates, :outreach, :outreach_status, :public_review, :reject_public_review, :vetting_queue, :approve_supporter, :reject_supporter ]
      before_action :require_supporter_access!, only: [ :index, :check_duplicate, :export, :show, :outreach, :outreach_status ]
      before_action :require_data_ops_access!, only: [ :revet, :bulk_revet, :duplicates, :resolve_duplicate, :scan_duplicates, :public_review, :reject_public_review, :vetting_queue, :approve_supporter, :reject_supporter ]
      before_action :require_chief_or_above!, only: [ :verify, :bulk_verify ]

      # POST /api/v1/supporters (public signup — no auth required)
      def create
        if staff_entry_mode?
          authenticate_request
          return if performed?
          require_staff_entry_access!
          return if performed?

          # Enforce village scope for staff entries by scoped users
          village_id = public_supporter_params[:village_id]
          if village_id.present? && scoped_village_ids && !scoped_village_ids.include?(village_id.to_i)
            return render json: { errors: [ "Village not in your assigned scope" ] }, status: :forbidden
          end
        end

        primary_attributes = normalized_public_supporter_params
        household_members = normalized_household_member_params
        if household_members.size > MAX_HOUSEHOLD_MEMBERS
          return render json: { errors: [ "You can add up to #{MAX_HOUSEHOLD_MEMBERS} household supporters per submission" ] }, status: :unprocessable_entity
        end
        normalized_leader_code = params[:leader_code].to_s.strip.presence
        referral_code = resolve_referral_code(normalized_leader_code)
        source = create_source
        attribution_method = create_attribution_method(normalized_leader_code)
        intake_status = create_intake_status(source)
        public_review_status = create_public_review_status(source)
        created_supporters = []
        duplicate_warning = false

        begin
          ApplicationRecord.transaction do
            household_group = build_household_group(primary_attributes, household_members)

            primary_supporter = build_submitted_supporter(
              primary_attributes,
              source: source,
              attribution_method: attribution_method,
              intake_status: intake_status,
              public_review_status: public_review_status,
              leader_code: normalized_leader_code,
              referral_code: referral_code,
              household_group: household_group,
              household_primary: household_group.present?,
              entered_by_user_id: current_user&.id
            )
            duplicate_warning ||= duplicate_detected?(primary_supporter)
            primary_supporter.save!
            log_created_supporter!(primary_supporter)
            created_supporters << primary_supporter

            household_members.each do |member_attributes|
              household_supporter = build_submitted_supporter(
                household_member_supporter_attributes(primary_attributes, member_attributes),
                source: source,
                attribution_method: attribution_method,
                intake_status: intake_status,
                public_review_status: public_review_status,
                leader_code: normalized_leader_code,
                referral_code: referral_code,
                household_group: household_group,
                household_primary: false,
                entered_by_user_id: current_user&.id
              )
              duplicate_warning ||= duplicate_detected?(household_supporter)
              household_supporter.save!
              log_created_supporter!(household_supporter)
              created_supporters << household_supporter
            end
          end
        rescue ActiveRecord::RecordInvalid => e
          return render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
        rescue ActiveRecord::StatementInvalid
          return render json: { errors: [ "Could not save this household signup. Please review the submission and try again." ] }, status: :unprocessable_entity
        end

        supporter = created_supporters.first

        # Queue welcome SMS so signup response is not blocked by external API latency.
        if supporter.contact_number.present? && supporter.opt_in_text
          SendSmsJob.perform_later(
            to: supporter.contact_number,
            body: SmsService.welcome_supporter_body(supporter)
          )
        end

        # Queue welcome email if supporter opted in
        if supporter.email.present? && supporter.opt_in_email
          SendWelcomeEmailJob.perform_later(supporter_id: supporter.id)
        end

        created_supporters.each do |created_supporter|
          created_supporter.reload
          CampaignBroadcast.new_supporter(created_supporter)
        end

        render json: {
          message: "Si Yu'os Ma'åse! Thank you for connecting with #{CampaignBranding::CAMPAIGN_LABEL}!",
          supporter: supporter_json(supporter),
          duplicate_warning: duplicate_warning || created_supporters.any?(&:potential_duplicate),
          household_supporters_created: [ created_supporters.size - 1, 0 ].max
        }, status: :created
      end

      # PATCH /api/v1/supporters/:id
      def update
        unless supporter_edit_allowed?
          return render_api_error(
            message: "You do not have permission to edit supporters",
            status: :forbidden,
            code: "supporter_edit_access_required"
          )
        end

        supporter = scope_supporters(Supporter).find(params[:id])
        updates = normalized_supporter_update_params
        # Clear the precinct so sync_precinct_assignment can re-assign it for
        # the new village instead of preserving the old precinct_id.
        if updates.key?(:village_id) && supporter.village_id != updates[:village_id].to_i && !updates.key?(:precinct_id)
          updates[:precinct_id] = nil
        end
        updates[:precinct_id] = nil if updates.key?(:precinct_id) && updates[:precinct_id].blank?

        if supporter.update(updates)
          changes = supporter.saved_changes.except("updated_at")
          log_audit!(supporter, action: "updated", changed_data: changes, normalize: true) if changes.present?
          CampaignBroadcast.supporter_updated(supporter, action: "updated")
          render json: { supporter: supporter_json(supporter) }
        else
          render_api_error(
            message: supporter.errors.full_messages.join(", "),
            status: :unprocessable_entity,
            code: "supporter_update_failed"
          )
        end
      end

      # PATCH /api/v1/supporters/:id/verify
      def verify
        supporter = scope_supporters(Supporter.includes(:referred_from_village)).find(params[:id])
        new_status = params[:verification_status]

        unless Supporter::VERIFICATION_STATUSES.include?(new_status)
          return render_api_error(
            message: "Invalid verification status. Must be: #{Supporter::VERIFICATION_STATUSES.join(', ')}",
            status: :unprocessable_entity,
            code: "invalid_verification_status"
          )
        end

        match_payload = new_status == "verified" ? verification_match_payload(supporter) : nil

        if new_status == "verified"
          matches = match_payload&.fetch(:matches, []) || []
          if matches.none?
            return render_api_error(
              message: "Supporter cannot be marked as a verified voter without a current GEC match.",
              status: :unprocessable_entity,
              code: "gec_match_required_for_verified"
            )
          end
        end

        old_status = supporter.verification_status
        supporter.update!(verification_update_attributes(supporter, new_status, match_payload: match_payload))

        log_audit!(supporter, action: "verification_changed", changed_data: {
          "verification_status" => [ old_status, new_status ],
          "verified_by" => current_user.name || current_user.email
        })
        CampaignBroadcast.supporter_updated(supporter, action: "verification_changed")

        render json: { supporter: supporter_json(supporter) }
      end

      # POST /api/v1/supporters/bulk_verify
      def bulk_verify
        ids = params[:supporter_ids]
        new_status = params[:verification_status] || "verified"

        unless ids.is_a?(Array) && ids.any?
          return render_api_error(
            message: "supporter_ids must be a non-empty array",
            status: :unprocessable_entity,
            code: "invalid_supporter_ids"
          )
        end

        unless Supporter::VERIFICATION_STATUSES.include?(new_status)
          return render_api_error(
            message: "Invalid verification status",
            status: :unprocessable_entity,
            code: "invalid_verification_status"
          )
        end

        supporters = scope_supporters(Supporter).where(id: ids).to_a
        count = supporters.size

        match_payloads = {}

        if new_status == "verified"
          supporters.each do |supporter|
            match_payloads[supporter.id] = verification_match_payload(supporter)
          end

          invalid_supporters = supporters.reject { |supporter| match_payloads.dig(supporter.id, :matches)&.any? }
          if invalid_supporters.any?
            return render_api_error(
              message: "One or more supporters cannot be marked as verified voters without a current GEC match.",
              status: :unprocessable_entity,
              code: "gec_match_required_for_verified"
            )
          end
        end

        # Capture old statuses before bulk update
        old_statuses = supporters.to_h { |supporter| [ supporter.id, supporter.verification_status ] }

        supporters.each do |supporter|
          supporter.update_columns(
            verification_update_attributes(
              supporter,
              new_status,
              match_payload: match_payloads[supporter.id]
            )
          )
        end

        # Audit log for each with accurate old status
        supporters.each do |s|
          old_status = old_statuses[s.id] || "unknown"
          log_audit!(s, action: "verification_changed", changed_data: {
            "verification_status" => [ old_status, new_status ],
            "verified_by" => current_user.name || current_user.email
          })
        end
        CampaignBroadcast.stats_update({
          reason: "bulk_verification_changed",
          updated_count: count,
          verification_status: new_status
        })

        render json: { updated: count, verification_status: new_status }
      end

      # GET /api/v1/supporters (authenticated)
      def index
        supporters = scope_supporters(
          Supporter.includes(
            :village,
            :submitted_village,
            :precinct,
            :block,
            :referred_from_village,
            household_group: :supporters
          ).official_supporters
        )

        # Filters
        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?
        if params[:unassigned_precinct] == "true"
          supporters = supporters.where(precinct_id: nil)
        elsif params[:precinct_id].present?
          supporters = supporters.where(precinct_id: params[:precinct_id])
        end
        supporters = supporters.where(status: params[:status]) if params[:status].present?
        supporters = supporters.where(source: params[:source]) if params[:source].present?
        supporters = supporters.where(review_status: params[:review_status]) if params[:review_status].present?
        supporters = supporters.where(public_review_status: params[:public_review_status]) if params[:public_review_status].present?
        supporters = supporters.where(registered_voter_status: params[:registered_voter_status]) if params[:registered_voter_status].present?
        supporters = supporters.where(registered_voter: true) if params[:registered_voter] == "true"
        supporters = apply_support_need_filter(supporters, params[:support_need])
        supporters = supporters.with_household if params[:has_household] == "true"
        supporters = supporters.team_input if params[:pipeline] == "team"
        supporters = supporters.public_origin if params[:pipeline] == "public"
        supporters = supporters.where(opt_in_email: true) if params[:opt_in_email] == "true"
        supporters = supporters.where(opt_in_text: true) if params[:opt_in_text] == "true"
        supporters = supporters.where(verification_status: params[:verification_status]) if params[:verification_status].present?

        if params[:search].present?
          raw = params[:search].to_s.strip
          sanitized = ActiveRecord::Base.sanitize_sql_like(raw)
          name_query = "%#{sanitized.downcase}%"
          phone_digits = raw.gsub(/\D/, "")
          if phone_digits.present?
            phone_query = "%#{ActiveRecord::Base.sanitize_sql_like(phone_digits)}%"
            supporters = supporters.where(
              "LOWER(supporters.print_name) LIKE :name_query OR LOWER(supporters.first_name) LIKE :name_query OR LOWER(supporters.last_name) LIKE :name_query OR regexp_replace(supporters.contact_number, '\\D', '', 'g') LIKE :phone_query",
              name_query: name_query,
              phone_query: phone_query
            )
          else
            supporters = supporters.where(
              "LOWER(supporters.print_name) LIKE :q OR LOWER(supporters.first_name) LIKE :q OR LOWER(supporters.last_name) LIKE :q",
              q: name_query
            )
          end
        end
        supporters = apply_index_sort(supporters)

        # Pagination
        page = [ (params[:page] || 1).to_i, 1 ].max
        requested_per_page = (params[:per_page] || 50).to_i
        per_page = requested_per_page.clamp(1, MAX_PER_PAGE)
        total = supporters.count
        supporters = supporters.offset((page - 1) * per_page).limit(per_page)

        legacy_flagged_supporters = supporters.select do |supporter|
          supporter.verification_status == "flagged" &&
            supporter.verification_reason.blank? &&
            supporter.referred_from_village_id.blank?
        end
        legacy_matches = GecVoter.find_matches_for_supporters(legacy_flagged_supporters)

        verification_reason_overrides = legacy_flagged_supporters.each_with_object({}) do |supporter, memo|
          memo[supporter.id] = SupporterVerificationReasonService.new(
            supporter,
            matches: legacy_matches[supporter.id] || []
          ).payload || {}
        end

        render json: {
          supporters: supporters.map { |s| supporter_json(s, reason_payload: verification_reason_overrides[s.id]) },
          pagination: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
        }
      end

      # GET /api/v1/supporters/:id
      def show
        supporter = scope_supporters(
          Supporter.includes(
            :village,
            :submitted_village,
            :precinct,
            :block,
            :referred_from_village,
            household_group: [ supporters: :village ]
          )
        ).find(params[:id])
        audit_logs = supporter.audit_logs.includes(:actor_user).recent.limit(50)

        render json: {
          supporter: supporter_detail_json(supporter),
          permissions: {
            can_edit: supporter_edit_allowed?
          },
          audit_logs: audit_logs.map do |log|
            {
              id: log.id,
              action: log.action,
              action_label: audit_action_label(log.action),
              actor_user_id: log.actor_user_id,
              actor_name: log.actor_user&.name,
              actor_role: log.actor_user&.role,
              changed_data: log.changed_data,
              metadata: log.metadata,
              created_at: log.created_at&.iso8601
            }
          end
        }
      end

      # GET /api/v1/supporters/export
      def export
        supporters = apply_export_filters(scope_supporters(Supporter.includes(:village, :precinct).official_supporters.order(created_at: :desc)))
        total = supporters.count

        if total > MAX_EXPORT_ROWS
          return render_api_error(
            message: "Export too large (#{total} rows). Please add filters to export up to #{MAX_EXPORT_ROWS} rows.",
            status: :unprocessable_entity,
            code: "supporters_export_too_large",
            details: { total_rows: total, max_rows: MAX_EXPORT_ROWS }
          )
        end

        headers = [ "First Name", "Last Name", "Phone", "Village", "Precinct", "Street Address", "Email", "DOB",
                    "Self-Reported Voter Status", "Votes Elsewhere Note", "Needs Registration Help", "Needs Absentee Help",
                    "Needs Homebound Help", "Needs Ride", "Wants To Volunteer", "Referred By", "Household Group",
"Opt-In Email", "Opt-In Text",
                    "Verification Status", "Source", "Date Signed Up" ]

        rows = []
        supporters.find_each do |s|
          rows << [
            s.first_name, s.last_name, s.contact_number, s.village&.name, s.precinct&.number,
            s.street_address, s.email, s.dob&.strftime("%m/%d/%Y"),
            s.registered_voter_status&.humanize,
            s.registered_voter_location_note,
            s.needs_voter_registration_help ? "Yes" : "No",
            s.needs_absentee_ballot_help ? "Yes" : "No",
            s.needs_homebound_voting_help ? "Yes" : "No",
            s.needs_election_day_ride ? "Yes" : "No",
            s.wants_to_volunteer ? "Yes" : "No",
            s.referred_by_name,
            s.household_group_id.present? ? "Yes" : "No",
            s.opt_in_email ? "Yes" : "No",
            s.opt_in_text ? "Yes" : "No",
            s.verification_status&.humanize,
            s.source&.humanize,
            s.created_at&.strftime("%m/%d/%Y")
          ]
        end

        format = params[:format_type] || "xlsx"
        if format == "csv"
          csv_data = CSV.generate(headers: true) do |csv|
            csv << headers
            rows.each { |r| csv << r }
          end

          send_data csv_data,
            filename: "supporters-#{Date.current.iso8601}.csv",
            type: "text/csv",
            disposition: "attachment"
        else
          package = Axlsx::Package.new
          wb = package.workbook
          wb.add_worksheet(name: "Supporters") do |sheet|
            header_style = wb.styles.add_style(b: true, bg_color: "1B3A6B", fg_color: "FFFFFF", alignment: { horizontal: :center })
            sheet.add_row headers, style: header_style
            rows.each { |r| sheet.add_row r }

            # Auto-width columns
            sheet.column_widths(*headers.map { |h| [ h.length + 4, 15 ].max })
          end

          send_data package.to_stream.read,
            filename: "supporters-#{Date.current.iso8601}.xlsx",
            type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            disposition: "attachment"
        end
      end

      # GET /api/v1/supporters/check_duplicate
      def check_duplicate
        name = params[:name]
        village_id = params[:village_id]
        dupes = Supporter.potential_duplicates(name, village_id, first_name: params[:first_name], last_name: params[:last_name])
        render json: { duplicates: dupes.map { |s| supporter_json(s) } }
      end

      # GET /api/v1/supporters/duplicates
      def duplicates
        scope = scope_supporters(Supporter.potential_duplicates_only.active)

        # Optional village filter
        scope = scope.where(village_id: params[:village_id]) if params[:village_id].present?

        scope = scope.includes(:village, :precinct, :duplicate_of).order(created_at: :desc)

        supporters = scope.limit(MAX_PER_PAGE)
        render json: {
          supporters: supporters.map { |s| supporter_json(s).merge(duplicate_info(s)) },
          total_count: scope.count
        }
      end

      # PATCH /api/v1/supporters/:id/resolve_duplicate
      def resolve_duplicate
        supporter = scope_supporters(Supporter).find(params[:id])
        action = params[:resolution] # "dismiss" or "merge"
        merge_target_snapshot = nil

        unless %w[dismiss merge].include?(action)
          return render_api_error(
            message: "resolution must be 'dismiss' or 'merge'",
            status: :unprocessable_entity,
            code: "invalid_resolution"
          )
        end

        merge_into = nil
        if action == "merge"
          merge_into = scope_supporters(Supporter).find_by(id: params[:merge_into_id])
          unless merge_into
            return render_api_error(
              message: "merge_into_id supporter not found",
              status: :not_found,
              code: "merge_target_not_found"
            )
          end
          merge_target_snapshot = merge_into.attributes.slice(*duplicate_merge_audit_fields)
        end

        DuplicateDetector.resolve!(supporter, action: action, merge_into: merge_into, resolved_by: current_user)
        supporter.reload
        merge_into.reload if merge_into

        log_audit!(supporter, action: "duplicate_resolved", changed_data: {
          "resolution" => action,
          "merge_into_id" => merge_into&.id
        }, normalize: true)
        if action == "merge" && merge_into
          kept_record_changes = { "merged_supporter_id" => supporter.id }
          duplicate_merge_audit_fields.each do |field|
            before_value = merge_target_snapshot[field]
            after_value = merge_into.public_send(field)
            next if before_value == after_value

            kept_record_changes[field] = [ before_value, after_value ]
          end

          log_audit!(merge_into, action: "duplicate_merged", changed_data: kept_record_changes, normalize: true)
          CampaignBroadcast.supporter_updated(merge_into, action: "duplicate_merged")
        end
        CampaignBroadcast.supporter_updated(supporter, action: "duplicate_resolved")

        render json: { message: "Duplicate #{action == 'merge' ? 'merged' : 'dismissed'}", supporter: supporter_json(supporter.reload) }
      end

      # GET /api/v1/supporters/outreach
      def outreach
        supporters = scope_supporters(Supporter.includes(:village, :submitted_village, :precinct, household_group: :supporters))
                       .working_supporters
                       .needs_follow_up

        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?

        if params[:queue_view].present?
          supporters = apply_outreach_queue_view(supporters, params[:queue_view])
        end

        registration_status_filter = params[:registration_outreach_status].presence || params[:outreach_status].presence
        if registration_status_filter == "not_contacted"
          supporters = supporters.where(registration_outreach_status: nil)
        elsif registration_status_filter.present?
          supporters = supporters.where(registration_outreach_status: registration_status_filter)
        end

        support_status_filter = params[:support_follow_up_status].presence
        if support_status_filter == "not_started"
          supporters = supporters.where(support_follow_up_status: nil)
        elsif support_status_filter.present?
          supporters = supporters.where(support_follow_up_status: support_status_filter)
        end

        supporters = supporters.where(registered_voter_status: params[:registered_voter_status]) if params[:registered_voter_status].present?
        supporters = apply_support_need_filter(supporters, params[:support_need])

        if params[:search].present?
          raw = params[:search].to_s.strip
          sanitized = ActiveRecord::Base.sanitize_sql_like(raw)
          name_query = "%#{sanitized.downcase}%"
          supporters = supporters.where(
            "LOWER(supporters.print_name) LIKE :q OR LOWER(supporters.first_name) LIKE :q OR LOWER(supporters.last_name) LIKE :q",
            q: name_query
          )
        end

        supporters = supporters.order(Arel.sql(outreach_priority_order_sql))

        page = [ (params[:page] || 1).to_i, 1 ].max
        per_page = (params[:per_page] || 50).to_i.clamp(1, MAX_PER_PAGE)
        total = supporters.count

        base_scope = scope_supporters(Supporter)
                       .working_supporters
                       .needs_follow_up
        base_scope = base_scope.where(village_id: params[:village_id]) if params[:village_id].present?
        open_scope = open_follow_up_scope(base_scope)
        completed_scope = completed_follow_up_scope(base_scope)
        registered_follow_up_count = base_scope.where(registration_outreach_status: "registered").count
        counts = {
          total: base_scope.count,
          open: open_scope.count,
          registration_priority: open_registration_follow_up_scope(base_scope).count,
          support_requests: open_support_follow_up_scope(base_scope).count,
          registered_follow_up: registered_follow_up_count,
          completed: completed_scope.count
        }

        supporters = supporters.offset((page - 1) * per_page).limit(per_page)

        render json: {
          supporters: supporters.map { |s| outreach_json(s) },
          counts: counts,
          pagination: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
        }
      end

      # PATCH /api/v1/supporters/:id/outreach_status
      def outreach_status
        supporter = scope_supporters(Supporter).find(params[:id])
        allowed_registration_statuses = %w[contacted registered declined]
        allowed_support_statuses = %w[in_progress completed declined]

        updates = {}
        if params.key?(:registration_outreach_status)
          if params[:registration_outreach_status].present?
            unless allowed_registration_statuses.include?(params[:registration_outreach_status])
              return render_api_error(
                message: "Invalid registration follow-up status. Must be: #{allowed_registration_statuses.join(', ')}",
                status: :unprocessable_entity,
                code: "invalid_outreach_status"
              )
            end
            updates[:registration_outreach_status] = params[:registration_outreach_status]
            updates[:registration_outreach_date] = Time.current
          else
            updates[:registration_outreach_status] = nil
            updates[:registration_outreach_date] = nil
          end
        end

        if params.key?(:support_follow_up_status)
          if params[:support_follow_up_status].present?
            unless allowed_support_statuses.include?(params[:support_follow_up_status])
              return render_api_error(
                message: "Invalid support follow-up status. Must be: #{allowed_support_statuses.join(', ')}",
                status: :unprocessable_entity,
                code: "invalid_support_follow_up_status"
              )
            end
            updates[:support_follow_up_status] = params[:support_follow_up_status]
            updates[:support_follow_up_date] = Time.current
          else
            updates[:support_follow_up_status] = nil
            updates[:support_follow_up_date] = nil
          end
        end

        updates[:registration_outreach_notes] = params[:registration_outreach_notes] if params.key?(:registration_outreach_notes)
        updates[:support_follow_up_notes] = params[:support_follow_up_notes] if params.key?(:support_follow_up_notes)

        if supporter.update(updates)
          changes = supporter.saved_changes.except("updated_at")
          log_audit!(supporter, action: "outreach_updated", changed_data: changes, normalize: true) if changes.present?
          render json: { supporter: outreach_json(supporter) }
        else
          render_api_error(
            message: supporter.errors.full_messages.join(", "),
            status: :unprocessable_entity,
            code: "outreach_update_failed"
          )
        end
      end

      # GET /api/v1/supporters/public_review
      # List self-submitted public signups waiting for intake review.
      def public_review
        supporters = public_review_scope

        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?

        if params[:search].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)
          supporters = supporters.where(
            "LOWER(supporters.first_name) LIKE :q OR LOWER(supporters.last_name) LIKE :q",
            q: "%#{sanitized.downcase}%"
          )
        end

        supporters = supporters.order(created_at: :desc)

        page = [ (params[:page] || 1).to_i, 1 ].max
        per_page = (params[:per_page] || 50).to_i.clamp(1, MAX_PER_PAGE)
        total = supporters.count
        supporters = supporters.offset((page - 1) * per_page).limit(per_page)

        summary_base = scope_supporters(Supporter.active)
        summary_base = summary_base.where(village_id: params[:village_id]) if params[:village_id].present?
        if params[:search].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)
          summary_base = summary_base.where(
            "LOWER(supporters.first_name) LIKE :q OR LOWER(supporters.last_name) LIKE :q",
            q: "%#{sanitized.downcase}%"
          )
        end
        pending_review_count = summary_base.public_signups.count
        accepted_count = summary_base.accepted_public_signups.count
        rejected_count = summary_base.public_review_rejected.count

        render json: {
          supporters: supporters.map { |s| supporter_json(s) },
          summary: {
            pending_review: pending_review_count,
            approved_for_supporter_review: accepted_count,
            accepted: accepted_count,
            rejected: rejected_count,
            total_public: pending_review_count + accepted_count + rejected_count
          },
          current_bucket: public_review_bucket,
          pagination: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
        }
      end

      # PATCH /api/v1/supporters/:id/reject_public_review
      def reject_public_review
        supporter = scope_supporters(Supporter).find(params[:id])

        unless supporter.public_review_status == "pending" && Supporter::PUBLIC_SOURCES.include?(supporter.source)
          return render_api_error(
            message: "Public submission has already been reviewed",
            status: :unprocessable_entity,
            code: "public_submission_already_reviewed"
          )
        end

        supporter.update!(
          public_review_status: "rejected",
          public_reviewed_at: Time.current,
          public_reviewed_by_user_id: current_user.id,
          review_status: "rejected",
          reviewed_at: Time.current,
          reviewed_by_user_id: current_user.id
        )
        DuplicateDetector.remove_candidate!(supporter)
        supporter.reload

        log_audit!(supporter, action: "public_review_rejected", changed_data: {
          "public_review_status" => [ "pending", "rejected" ],
          "review_status" => [ "pending", "rejected" ]
        }, normalize: true)

        CampaignBroadcast.supporter_updated(supporter, action: "public_review_rejected")
        render json: { supporter: supporter_json(supporter), message: "Public submission rejected" }
      end

      # PATCH /api/v1/supporters/:id/approve_supporter
      def approve_supporter
        supporter = scope_supporters(Supporter).find(params[:id])

        unless supporter.review_status == "pending" && supporter.public_review_status != "pending"
          return render_api_error(
            message: "Supporter submission is not ready for approval",
            status: :unprocessable_entity,
            code: "supporter_review_not_pending"
          )
        end

        if supporter.potential_duplicate?
          return render_api_error(
            message: "Supporter has an unresolved duplicate warning",
            status: :unprocessable_entity,
            code: "duplicate_review_required"
          )
        end

        supporter.update!(
          review_status: "approved",
          reviewed_at: Time.current,
          reviewed_by_user_id: current_user.id
        )

        log_audit!(supporter, action: "supporter_review_approved", changed_data: {
          "review_status" => [ "pending", "approved" ]
        }, normalize: true)
        CampaignBroadcast.supporter_updated(supporter, action: "supporter_review_approved")

        render json: { supporter: supporter_json(supporter), message: "Supporter approved into the official supporter list" }
      end

      # PATCH /api/v1/supporters/:id/reject_supporter
      def reject_supporter
        supporter = scope_supporters(Supporter).find(params[:id])

        unless supporter.review_status == "pending" && supporter.public_review_status != "pending"
          return render_api_error(
            message: "Supporter submission is not ready for rejection",
            status: :unprocessable_entity,
            code: "supporter_review_not_pending"
          )
        end

        supporter.update!(
          review_status: "rejected",
          reviewed_at: Time.current,
          reviewed_by_user_id: current_user.id
        )
        DuplicateDetector.remove_candidate!(supporter)
        supporter.reload

        log_audit!(supporter, action: "supporter_review_rejected", changed_data: {
          "review_status" => [ "pending", "rejected" ]
        }, normalize: true)
        CampaignBroadcast.supporter_updated(supporter, action: "supporter_review_rejected")

        render json: { supporter: supporter_json(supporter), message: "Supporter submission rejected" }
      end

      # PATCH /api/v1/supporters/:id/revet
      def revet
        supporter = scope_supporters(Supporter).find(params[:id])
        result = GecVettingService.new(supporter).call
        supporter.reload

        log_audit!(supporter, action: "supporter_re_vetted", changed_data: {
          "verification_status" => supporter.verification_status,
          "registered_voter" => supporter.registered_voter,
          "verification_reason" => supporter.verification_reason
        }, normalize: true)

        render json: {
          supporter: supporter_json(supporter),
          result: {
            status: result.status,
            details: result.details,
            match_count: result.match_count
          }
        }
      end

      # POST /api/v1/supporters/bulk_revet
      def bulk_revet
        supporters = bulk_revet_scope
        if supporters.none?
          return render_api_error(
            message: "No supporters matched the bulk re-vet request",
            status: :unprocessable_entity,
            code: "invalid_supporter_ids"
          )
        end

        supporter_ids = supporters.pluck(:id)
        results = Hash.new(0)
        updated_count = 0

        supporters.find_each do |supporter|
          result = GecVettingService.new(supporter).call
          results[result.status] += 1
          updated_count += 1
        rescue StandardError => e
          results[:errors] += 1
          Rails.logger.warn("Queue bulk re-vet error for supporter #{supporter.id}: #{e.message}")
        end

        log_audit!(nil, action: "supporter_queue_bulk_re_vet", changed_data: {
          supporter_ids: supporter_ids,
          results: results
        }, normalize: true)

        render json: {
          message: "Queue re-vet complete",
          updated: updated_count,
          results: results
        }
      end

      # GET /api/v1/supporters/vetting_queue
      # Supporter review workspace for pending, approved, and rejected submissions.
      def vetting_queue
        base = vetting_queue_base_scope
        queue_scope = vetting_queue_bucket_scope(base)
        scope = vetting_queue_filter_scope(queue_scope)

        scope = scope.order(created_at: :desc)

        page = [ (params[:page] || 1).to_i, 1 ].max
        per_page = (params[:per_page] || 50).to_i.clamp(1, MAX_PER_PAGE)
        total = scope.count
        supporters = scope.offset((page - 1) * per_page).limit(per_page)

        # GEC match lookup per supporter — O(n) queries where n = supporters per page (max 50).
        # Each lookup uses compound indexes on (lower(first_name), lower(last_name), dob)
        # and cascading match strategies that are hard to batch. With indexed queries and
        # capped page size, this stays well under 100ms total.
        gec_matches = {}
        verification_reasons = {}
        supporters.each do |s|
          matches = GecVoter.find_matches(
            first_name: s.first_name,
            last_name: s.last_name,
            dob: s.dob,
            village_name: s.village&.name
          )
          verification_reasons[s.id] = SupporterVerificationReasonService.new(s, matches: matches).payload || {}
          gec_matches[s.id] = matches.first(3).map do |m|
            {
              gec_voter: m[:gec_voter].as_json(only: [ :id, :first_name, :middle_name, :last_name, :dob, :birth_year, :address, :village_name, :village_id, :precinct_id, :precinct_number, :previous_village_name, :voter_registration_number, :status, :gec_list_date ]),
              confidence: m[:confidence],
              match_type: m[:match_type],
              match_count: m[:match_count]
            }
          end
        end

        # Summary counts within the currently selected structural filters
        summary = {
          pending: base.review_pending.count,
          approved: base.review_approved.count,
          rejected: base.review_rejected.count,
          total_pending_review: base.review_pending.count,
          total_needing_review: queue_scope.count,
          verified: queue_scope.verified.count,
          flagged: queue_scope.flagged.where.not(id: queue_scope.submitted_village_referrals.select(:id)).count,
          unverified: queue_scope.unverified.where(registered_voter: false).count,
          no_match: queue_scope.unverified.where(registered_voter: false).count,
          unregistered: queue_scope.unverified.where(registered_voter: false).count,
          referrals: queue_scope.submitted_village_referrals.count,
          registration_help: queue_scope.where(needs_voter_registration_help: true).count,
          help_requests: queue_scope.needs_campaign_help.count
        }

        render json: {
          supporters: supporters.map do |s|
            supporter_json(s, reason_payload: verification_reasons[s.id]).merge(
              gec_matches: gec_matches[s.id] || []
            )
          end,
          summary: summary,
          current_bucket: vetting_queue_bucket,
          pagination: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
        }
      end

      # POST /api/v1/supporters/scan_duplicates
      def scan_duplicates
        count = DuplicateDetector.scan_all!
        render json: { message: "Scan complete", flagged_count: count }
      end

      private

      def apply_export_filters(supporters)
        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?
        if params[:unassigned_precinct] == "true"
          supporters = supporters.where(precinct_id: nil)
        elsif params[:precinct_id].present?
          supporters = supporters.where(precinct_id: params[:precinct_id])
        end
        supporters = supporters.where(status: params[:status]) if params[:status].present?
        supporters = supporters.where(source: params[:source]) if params[:source].present?
        supporters = supporters.where(review_status: params[:review_status]) if params[:review_status].present?
        supporters = supporters.where(public_review_status: params[:public_review_status]) if params[:public_review_status].present?
        supporters = supporters.where(registered_voter_status: params[:registered_voter_status]) if params[:registered_voter_status].present?
        supporters = supporters.where(registered_voter: true) if params[:registered_voter] == "true"
        supporters = apply_support_need_filter(supporters, params[:support_need])
        supporters = supporters.with_household if params[:has_household] == "true"
        supporters = supporters.team_input if params[:pipeline] == "team"
        supporters = supporters.public_origin if params[:pipeline] == "public"
        supporters = supporters.where(opt_in_email: true) if params[:opt_in_email] == "true"
        supporters = supporters.where(opt_in_text: true) if params[:opt_in_text] == "true"
        supporters = supporters.where(verification_status: params[:verification_status]) if params[:verification_status].present?

        if params[:search].present?
          raw = params[:search].to_s.strip
          sanitized = ActiveRecord::Base.sanitize_sql_like(raw)
          name_query = "%#{sanitized.downcase}%"
          phone_digits = raw.gsub(/\D/, "")
          if phone_digits.present?
            phone_query = "%#{ActiveRecord::Base.sanitize_sql_like(phone_digits)}%"
            supporters = supporters.where(
              "LOWER(supporters.print_name) LIKE :name_query OR LOWER(supporters.first_name) LIKE :name_query OR LOWER(supporters.last_name) LIKE :name_query OR regexp_replace(supporters.contact_number, '\\D', '', 'g') LIKE :phone_query",
              name_query: name_query,
              phone_query: phone_query
            )
          else
            supporters = supporters.where(
              "LOWER(supporters.print_name) LIKE :q OR LOWER(supporters.first_name) LIKE :q OR LOWER(supporters.last_name) LIKE :q",
              q: name_query
            )
          end
        end

        apply_index_sort(supporters)
      end

      def public_supporter_params
        permitted = [
          :first_name, :middle_name, :last_name, :print_name, :contact_number, :dob, :email, :street_address,
          :village_id, :precinct_id, :registered_voter, :self_reported_registered_voter, :registered_voter_status,
          :registered_voter_location_note, :wants_to_volunteer, :needs_absentee_ballot_help,
          :needs_homebound_voting_help, :needs_voter_registration_help, :needs_election_day_ride, :referred_by_name,
          :opt_in_email, :opt_in_text,
          household_members: [
            :first_name, :middle_name, :last_name, :dob,
            :registered_voter, :self_reported_registered_voter, :registered_voter_status,
            :registered_voter_location_note, :wants_to_volunteer, :needs_absentee_ballot_help,
            :needs_homebound_voting_help, :needs_voter_registration_help, :needs_election_day_ride
          ]
        ]
        permitted << :submitted_village_id if staff_entry_mode?
        params.require(:supporter).permit(*permitted)
      end

      def supporter_update_params
        params.require(:supporter).permit(
          :first_name, :middle_name, :last_name, :print_name, :contact_number, :email, :dob, :street_address,
          :village_id, :submitted_village_id, :precinct_id, :registered_voter, :self_reported_registered_voter, :registered_voter_status,
          :registered_voter_location_note, :wants_to_volunteer, :needs_absentee_ballot_help,
          :needs_homebound_voting_help, :needs_voter_registration_help, :needs_election_day_ride, :referred_by_name,
          :household_primary,
          :opt_in_email, :opt_in_text, :status
        )
      end

      def normalized_public_supporter_params
        normalize_registered_voter_fields(public_supporter_params.to_h.except("household_members"))
      end

      def normalized_household_member_params
        Array(public_supporter_params.to_h["household_members"]).map { |member| normalize_registered_voter_fields(member) }
          .reject { |member| member["first_name"].blank? && member["last_name"].blank? }
      end

      def normalized_supporter_update_params
        normalize_registered_voter_fields(supporter_update_params.to_h)
      end

      def normalize_registered_voter_fields(attributes)
        if attributes.key?("registered_voter_status")
          attributes["self_reported_registered_voter"] =
            case attributes["registered_voter_status"]
            when "yes"
              true
            when "no"
              false
            else
              nil
            end
        elsif !attributes.key?("self_reported_registered_voter") && attributes.key?("registered_voter")
          attributes["self_reported_registered_voter"] = attributes["registered_voter"]
          attributes["registered_voter_status"] = attributes["registered_voter"] ? "yes" : "no"
        elsif attributes.key?("self_reported_registered_voter")
          attributes["registered_voter_status"] =
            case attributes["self_reported_registered_voter"]
            when true
              "yes"
            when false
              "no"
            else
              "not_sure"
            end
        end

        attributes
      end

      def create_source
        return "qr_signup" if params[:leader_code].to_s.strip.present?
        return "staff_entry" if staff_entry_mode?

        # Public signup without a leader/referral code.
        "public_signup"
      end

      def create_attribution_method(normalized_leader_code)
        return "qr_self_signup" if normalized_leader_code.present?
        return params[:entry_channel] == "scan" ? "staff_scan" : "staff_manual" if staff_entry_mode?

        "public_signup"
      end

      def create_intake_status(source)
        Supporter::PUBLIC_SOURCES.include?(source) ? "pending_public_review" : "accepted"
      end

      def create_public_review_status(source)
        Supporter::PUBLIC_SOURCES.include?(source) ? "pending" : "not_applicable"
      end

      def public_review_bucket
        bucket = params[:review_bucket].to_s.presence || "pending"
        %w[pending approved rejected].include?(bucket) ? bucket : "pending"
      end

      def vetting_queue_bucket
        bucket = params[:review_bucket].to_s.presence || "pending"
        %w[pending approved rejected].include?(bucket) ? bucket : "pending"
      end

      def public_review_scope
        base = scope_supporters(Supporter.includes(:village, :submitted_village, :precinct, household_group: :supporters)).active

        case public_review_bucket
        when "approved"
          base.public_review_approved
        when "rejected"
          base.public_review_rejected
        else
          base.pending_public_review
        end
      end

      def staff_entry_mode?
        params[:entry_mode] == "staff"
      end

      def bulk_revet_scope
        if ActiveModel::Type::Boolean.new.cast(params[:apply_current_filters])
          vetting_queue_filter_scope(vetting_queue_bucket_scope(vetting_queue_base_scope))
        else
          ids = Array(params[:supporter_ids]).map(&:to_i).uniq
          return Supporter.none if ids.empty?

          scope_supporters(Supporter).where(id: ids)
        end
      end

      def vetting_queue_base_scope
        base = scope_supporters(Supporter.includes(:village, :submitted_village, :precinct, :entered_by, household_group: :supporters))
          .where(public_review_status: %w[approved not_applicable])

        if params[:district_id].present?
          base = base.joins(:village).where(villages: { district_id: params[:district_id] })
        end
        base = base.where(village_id: params[:village_id]) if params[:village_id].present?
        base = base.where(precinct_id: params[:precinct_id]) if params[:precinct_id].present?

        if params[:source_group] == "team"
          base = base.where(source: Supporter::TEAM_SOURCES)
        elsif params[:source].present?
          base = base.where(source: params[:source])
        end

        if params[:search].present?
          base = apply_loose_supporter_search(base, params[:search])
        end

        base
      end

      def vetting_queue_bucket_scope(base)
        case vetting_queue_bucket
        when "approved"
          base.review_approved
        when "rejected"
          base.review_rejected
        else
          base.review_pending
        end
      end

      def vetting_queue_filter_scope(queue_scope)
        case params[:filter]
        when "verified"
          queue_scope.verified
        when "flagged"
          queue_scope.flagged.where.not(id: queue_scope.submitted_village_referrals.select(:id))
        when "no_match", "unregistered"
          queue_scope.unverified.where(registered_voter: false)
        when "referral"
          queue_scope.submitted_village_referrals
        when "registration_help"
          queue_scope.where(needs_voter_registration_help: true)
        when "help_requests"
          queue_scope.needs_campaign_help
        else
          queue_scope
        end
      end

      def apply_loose_supporter_search(scope, query)
        tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?).first(6)
        return scope if tokens.empty?

        tokens.reduce(scope) do |relation, token|
          sanitized = ActiveRecord::Base.sanitize_sql_like(token)
          pattern = "%#{sanitized}%"
          relation.where(
            "LOWER(supporters.first_name) LIKE :pattern OR LOWER(supporters.middle_name) LIKE :pattern OR LOWER(supporters.last_name) LIKE :pattern OR LOWER(supporters.print_name) LIKE :pattern OR LOWER(supporters.contact_number) LIKE :pattern",
            pattern: pattern
          )
        end
      end

      def supporter_json(supporter, reason_payload: nil)
        reason_payload ||= SupporterVerificationReasonService.new(supporter).payload || {}
        current_gec_match = supporter.gec_voter_id.present?

        {
          id: supporter.id,
          first_name: supporter.first_name,
          middle_name: supporter.middle_name,
          last_name: supporter.last_name,
          print_name: supporter.print_name,
          contact_number: supporter.contact_number,
          dob: supporter.dob,
          email: supporter.email,
          street_address: supporter.street_address,
          village_id: supporter.village_id,
          village_name: supporter.village&.name,
          submitted_village_id: supporter.submitted_village_id,
          submitted_village_name: supporter.submitted_village&.name,
          submitted_village_referral: supporter.submitted_village_referral?,
          precinct_id: supporter.precinct_id,
          precinct_number: supporter.precinct&.number,
          block_id: supporter.block_id,
          self_reported_registered_voter: supporter.self_reported_registered_voter,
          registered_voter_status: supporter.registered_voter_status,
          registered_voter_location_note: supporter.registered_voter_location_note,
          registered_voter: supporter.registered_voter,
          current_gec_match: current_gec_match,
          wants_to_volunteer: supporter.wants_to_volunteer,
          needs_absentee_ballot_help: supporter.needs_absentee_ballot_help,
          needs_homebound_voting_help: supporter.needs_homebound_voting_help,
          needs_voter_registration_help: supporter.needs_voter_registration_help,
          needs_election_day_ride: supporter.needs_election_day_ride,
          referred_by_name: supporter.referred_by_name,
          opt_in_email: supporter.opt_in_email,
          opt_in_text: supporter.opt_in_text,
          verification_status: supporter.verification_status,
          verified_at: supporter.verified_at&.iso8601,
          verified_by_user_id: supporter.verified_by_user_id,
          source: supporter.source,
          intake_status: supporter.intake_status,
          review_status: supporter.review_status,
          public_review_status: supporter.public_review_status,
          reviewed_at: supporter.reviewed_at&.iso8601,
          reviewed_by_user_id: supporter.reviewed_by_user_id,
          public_reviewed_at: supporter.public_reviewed_at&.iso8601,
          public_reviewed_by_user_id: supporter.public_reviewed_by_user_id,
          status: supporter.status,
          leader_code: supporter.leader_code,
          attribution_method: supporter.attribution_method,
          referral_code_id: supporter.referral_code_id,
          referral_display_name: supporter.referral_code&.display_name,
          referred_from_village_id: supporter.referred_from_village_id,
          referred_from_village_name: supporter.referred_from_village&.name,
          verification_reason: reason_payload[:verification_reason],
          verification_reason_label: reason_payload[:verification_reason_label],
          verification_reason_detail: reason_payload[:verification_reason_detail],
          verification_reason_metadata: reason_payload[:verification_reason_metadata],
          verification_reason_derived: reason_payload[:verification_reason_derived],
          potential_duplicate: supporter.potential_duplicate,
          duplicate_of_id: supporter.duplicate_of_id,
          duplicate_notes: supporter.duplicate_notes,
          household_group_id: supporter.household_group_id,
          household_primary: supporter.household_primary,
          household_member_count: household_member_count(supporter),
          registration_outreach_status: supporter.registration_outreach_status,
          registration_outreach_notes: supporter.registration_outreach_notes,
          registration_outreach_date: supporter.registration_outreach_date&.iso8601,
          support_follow_up_status: supporter.support_follow_up_status,
          support_follow_up_notes: supporter.support_follow_up_notes,
          support_follow_up_date: supporter.support_follow_up_date&.iso8601,
          created_at: supporter.created_at&.iso8601
        }
      end

      def outreach_json(supporter)
        current_gec_match = supporter.gec_voter_id.present?

        {
          id: supporter.id,
          first_name: supporter.first_name,
          middle_name: supporter.middle_name,
          last_name: supporter.last_name,
          print_name: supporter.print_name,
          contact_number: supporter.contact_number,
          email: supporter.email,
          village_id: supporter.village_id,
          village_name: supporter.village&.name,
          precinct_number: supporter.precinct&.number,
          registered_voter_status: supporter.registered_voter_status,
          registered_voter_location_note: supporter.registered_voter_location_note,
          registered_voter: supporter.registered_voter,
          current_gec_match: current_gec_match,
          wants_to_volunteer: supporter.wants_to_volunteer,
          needs_absentee_ballot_help: supporter.needs_absentee_ballot_help,
          needs_homebound_voting_help: supporter.needs_homebound_voting_help,
          needs_voter_registration_help: supporter.needs_voter_registration_help,
          needs_election_day_ride: supporter.needs_election_day_ride,
          referred_by_name: supporter.referred_by_name,
          household_group_id: supporter.household_group_id,
          household_member_count: household_member_count(supporter),
          follow_up_priority: outreach_priority_label(supporter),
          follow_up_reasons: outreach_reasons(supporter),
          needs_registration_follow_up: needs_registration_follow_up?(supporter),
          needs_support_follow_up: needs_support_follow_up?(supporter),
          registration_follow_up_open: registration_follow_up_open?(supporter),
          support_follow_up_open: support_follow_up_open?(supporter),
          follow_up_open: follow_up_open?(supporter),
          registration_outreach_status: supporter.registration_outreach_status,
          registration_outreach_notes: supporter.registration_outreach_notes,
          registration_outreach_date: supporter.registration_outreach_date&.iso8601,
          support_follow_up_status: supporter.support_follow_up_status,
          support_follow_up_notes: supporter.support_follow_up_notes,
          support_follow_up_date: supporter.support_follow_up_date&.iso8601,
          status: supporter.status,
          created_at: supporter.created_at&.iso8601
        }
      end

      def supporter_detail_json(supporter)
        reason_payload = SupporterVerificationReasonService.new(supporter, allow_match_lookup: true).payload || {}

        supporter_json(supporter, reason_payload: reason_payload).merge(
          block_name: supporter.block&.name,
          household_members: supporter.household_members.map do |member|
            {
              id: member.id,
              first_name: member.first_name,
              middle_name: member.middle_name,
              last_name: member.last_name,
              print_name: member.print_name,
              village_name: member.village&.name,
              registered_voter_status: member.registered_voter_status,
              review_status: member.review_status,
              public_review_status: member.public_review_status
            }
          end
        )
      end

      def duplicate_info(supporter)
        info = {}
        if supporter.duplicate_of_id.present? && supporter.association(:duplicate_of).loaded?
          orig = supporter.duplicate_of
          info[:duplicate_of] = orig ? { id: orig.id, name: orig.display_name, contact_number: orig.contact_number } : nil
        end
        info
      end

      def audit_entry_mode
        params[:entry_mode]
      end

      def supporter_audit_metadata(supporter)
        { leader_code: params[:leader_code], referral_code_id: supporter.referral_code_id }.compact
      end

      def resolve_referral_code(code)
        normalized = code.to_s.strip
        return nil if normalized.blank?

        ReferralCode.find_by(code: normalized)
      end

      def supporter_edit_allowed?
        current_user&.admin? || current_user&.data_team? || current_user&.coordinator?
      end

      def build_household_group(primary_attributes, household_members)
        return nil if household_members.empty?

        HouseholdGroup.create!(
          village_id: primary_attributes["village_id"],
          shared_contact_number: primary_attributes["contact_number"].presence,
          shared_email: primary_attributes["email"].presence,
          street_address: primary_attributes["street_address"].presence
        )
      end

      def build_submitted_supporter(attributes, source:, attribution_method:, intake_status:, public_review_status:, leader_code:, referral_code:, household_group:, household_primary:, entered_by_user_id:)
        supporter = Supporter.new(attributes)
        supporter.source = source
        supporter.attribution_method = attribution_method
        supporter.intake_status = intake_status
        supporter.review_status = Supporter::PUBLIC_SOURCES.include?(source) ? "pending" : "approved"
        supporter.public_review_status = public_review_status
        supporter.status = "active"
        supporter.leader_code = leader_code
        supporter.referral_code = referral_code if referral_code
        supporter.household_group = household_group if household_group
        supporter.household_primary = household_group.present? && household_primary
        supporter.entered_by_user_id = entered_by_user_id if staff_entry_mode? && entered_by_user_id.present?
        supporter.registered_voter = false if supporter.registered_voter.nil?
        supporter.wants_to_volunteer = false if supporter.wants_to_volunteer.nil?
        supporter.needs_absentee_ballot_help = false if supporter.needs_absentee_ballot_help.nil?
        supporter.needs_homebound_voting_help = false if supporter.needs_homebound_voting_help.nil?
        supporter.needs_voter_registration_help = false if supporter.needs_voter_registration_help.nil?
        supporter.needs_election_day_ride = false if supporter.needs_election_day_ride.nil?
        supporter
      end

      def household_member_supporter_attributes(primary_attributes, member_attributes)
        {
          "first_name" => member_attributes["first_name"],
          "middle_name" => member_attributes["middle_name"],
          "last_name" => member_attributes["last_name"],
          "dob" => member_attributes["dob"],
          "contact_number" => primary_attributes["contact_number"],
          "email" => primary_attributes["email"],
          "street_address" => primary_attributes["street_address"],
          "village_id" => primary_attributes["village_id"],
          "submitted_village_id" => primary_attributes["submitted_village_id"],
          "registered_voter_status" => member_attributes["registered_voter_status"],
          "registered_voter_location_note" => member_attributes["registered_voter_location_note"],
          "self_reported_registered_voter" => member_attributes["self_reported_registered_voter"],
          "wants_to_volunteer" => member_attributes["wants_to_volunteer"],
          "needs_absentee_ballot_help" => member_attributes["needs_absentee_ballot_help"],
          "needs_homebound_voting_help" => member_attributes["needs_homebound_voting_help"],
          "needs_voter_registration_help" => member_attributes["needs_voter_registration_help"],
          "needs_election_day_ride" => member_attributes["needs_election_day_ride"],
          "referred_by_name" => primary_attributes["referred_by_name"],
          "opt_in_email" => false,
          "opt_in_text" => false
        }
      end

      def duplicate_detected?(supporter)
        Supporter.potential_duplicates(
          supporter.print_name,
          supporter.village_id,
          first_name: supporter.first_name,
          last_name: supporter.last_name
        ).exists?
      end

      def log_created_supporter!(supporter)
        log_audit!(
          supporter,
          action: "created",
          changed_data: supporter.saved_changes.except("updated_at"),
          normalize: true,
          metadata: supporter_audit_metadata(supporter)
        )
      end

      def apply_support_need_filter(scope, filter)
        case filter
        when "registration"
          scope.where(needs_voter_registration_help: true)
        when "absentee"
          scope.where(needs_absentee_ballot_help: true)
        when "homebound"
          scope.where(needs_homebound_voting_help: true)
        when "ride"
          scope.where(needs_election_day_ride: true)
        when "volunteer"
          scope.where(wants_to_volunteer: true)
        when "any"
          scope.needs_campaign_help
        else
          scope
        end
      end

      def apply_outreach_queue_view(scope, queue_view)
        case queue_view
        when "open"
          open_follow_up_scope(scope)
        when "registration_priority"
          open_registration_follow_up_scope(scope)
        when "support_requests"
          open_support_follow_up_scope(scope)
        when "registered_follow_up"
          scope.where(registration_outreach_status: "registered")
        when "completed"
          completed_follow_up_scope(scope)
        else
          scope
        end
      end

      def open_follow_up_scope(scope)
        open_registration_follow_up_scope(scope).or(open_support_follow_up_scope(scope))
      end

      def open_registration_follow_up_scope(scope)
        registration_priority_scope(scope).where(registration_outreach_status: [ nil, "contacted" ])
      end

      def open_support_follow_up_scope(scope)
        support_follow_up_scope(scope).where(support_follow_up_status: [ nil, "in_progress" ])
      end

      def completed_follow_up_scope(scope)
        scope.where.not(id: open_follow_up_scope(scope).select(:id))
      end

      def registration_priority_scope(scope)
        scope.where(needs_voter_registration_help: true)
             .or(scope.where(registered_voter: false))
             .or(scope.where(registered_voter_status: %w[no not_sure]))
      end

      def support_follow_up_scope(scope)
        scope.needs_support_services
      end

      def outreach_priority_order_sql
        <<~SQL.squish
          CASE
            WHEN supporters.registration_outreach_status IS NULL AND supporters.needs_voter_registration_help = TRUE THEN 12
            WHEN supporters.registration_outreach_status IS NULL AND supporters.registered_voter = FALSE THEN 11
            WHEN supporters.registration_outreach_status IS NULL AND supporters.registered_voter_status = 'no' THEN 10
            WHEN supporters.registration_outreach_status IS NULL AND supporters.registered_voter_status = 'not_sure' THEN 9
            WHEN supporters.support_follow_up_status IS NULL AND (
              supporters.needs_absentee_ballot_help = TRUE OR
              supporters.needs_homebound_voting_help = TRUE OR
              supporters.needs_election_day_ride = TRUE
            ) THEN 8
            WHEN supporters.support_follow_up_status IS NULL AND supporters.wants_to_volunteer = TRUE THEN 7
            WHEN supporters.registration_outreach_status = 'contacted' THEN 6
            WHEN supporters.support_follow_up_status = 'in_progress' THEN 5
            WHEN supporters.registration_outreach_status = 'registered' THEN 2
            WHEN supporters.support_follow_up_status = 'completed' THEN 2
            WHEN supporters.registration_outreach_status = 'declined' OR supporters.support_follow_up_status = 'declined' THEN 1
            ELSE 0
          END DESC,
          COALESCE(supporters.registration_outreach_date, supporters.support_follow_up_date, supporters.created_at) ASC,
          supporters.created_at ASC
        SQL
      end

      def outreach_priority_label(supporter)
        return "Resolved" unless follow_up_open?(supporter)
        return "Registration Priority" if registration_follow_up_open?(supporter)
        "Support Help"
      end

      def outreach_reasons(supporter)
        reasons = []
        reasons.concat(registration_follow_up_reasons(supporter))
        reasons.concat(support_request_reasons(supporter))
        reasons << "Registered via follow-up" if supporter.registration_outreach_status == "registered"
        reasons << "Registration follow-up declined" if supporter.registration_outreach_status == "declined"
        reasons << "Support help completed" if supporter.support_follow_up_status == "completed"
        reasons << "Support help declined" if supporter.support_follow_up_status == "declined"
        reasons.uniq
      end

      def registration_follow_up_reasons(supporter)
        reasons = []
        reasons << "Needs registration help" if supporter.needs_voter_registration_help
        reasons << "No GEC match" unless supporter.registered_voter
        reasons << "Self-reported not registered" if supporter.registered_voter_status == "no"
        reasons << "Self-reported not sure" if supporter.registered_voter_status == "not_sure"
        reasons
      end

      def support_request_reasons(supporter)
        reasons = []
        reasons << "Absentee help" if supporter.needs_absentee_ballot_help
        reasons << "Homebound help" if supporter.needs_homebound_voting_help
        reasons << "Ride to polls" if supporter.needs_election_day_ride
        reasons << "Volunteer interest" if supporter.wants_to_volunteer
        reasons
      end

      def needs_registration_follow_up?(supporter)
        supporter.needs_voter_registration_help || !supporter.registered_voter || supporter.registered_voter_status.in?(%w[no not_sure])
      end

      def needs_support_follow_up?(supporter)
        support_request_reasons(supporter).present?
      end

      def registration_follow_up_open?(supporter)
        needs_registration_follow_up?(supporter) && supporter.registration_outreach_status.in?([ nil, "contacted" ])
      end

      def support_follow_up_open?(supporter)
        needs_support_follow_up?(supporter) && supporter.support_follow_up_status.in?([ nil, "in_progress" ])
      end

      def follow_up_open?(supporter)
        registration_follow_up_open?(supporter) || support_follow_up_open?(supporter)
      end

      def household_member_count(supporter)
        return 0 unless supporter.household_group_id.present?

        group = supporter.household_group
        return 0 unless group.present?

        linked_supporter_count =
          if supporter.association(:household_group).loaded? && group.association(:supporters).loaded?
            group.supporters.size
          else
            group.supporters.count
          end

        [ linked_supporter_count - 1, 0 ].max
      end

      def verification_update_attributes(supporter, new_status, match_payload: nil)
        attrs = { verification_status: new_status }
        if new_status == "verified"
          best_match = (match_payload || verification_match_payload(supporter))[:best_match]
          gec_voter = best_match&.dig(:gec_voter)
          attrs.merge!(
            gec_voter_id: gec_voter&.id,
            precinct_id: gec_voter&.precinct_id || supporter.precinct_id,
            verified_by_user_id: current_user.id,
            verified_at: Time.current,
            verification_reason: "manual_staff_verified",
            verification_reason_metadata: {
              "gec_village_name" => gec_voter&.village_name,
              "confidence" => best_match&.dig(:confidence)&.to_s,
              "match_type" => best_match&.dig(:match_type)&.to_s,
              "match_count" => best_match&.dig(:match_count)
            }.compact,
            referred_from_village_id: nil
          )
        elsif new_status == "flagged"
          attrs.merge!(
            gec_voter_id: nil,
            verified_by_user_id: nil,
            verified_at: nil,
            verification_reason: "manual_staff_flag",
            verification_reason_metadata: {},
            referred_from_village_id: nil
          )
        else
          attrs.merge!(
            gec_voter_id: nil,
            verified_by_user_id: nil,
            verified_at: nil,
            verification_reason: nil,
            verification_reason_metadata: {},
            referred_from_village_id: nil
          )
        end
        attrs
      end

      def verification_match_payload(supporter)
        matches = GecVoter.find_matches(
          first_name: supporter.first_name,
          last_name: supporter.last_name,
          dob: supporter.dob,
          birth_year: supporter.dob&.year,
          village_name: supporter.village&.name
        )

        {
          matches: matches,
          best_match: matches.first
        }
      end

      # Alias for backward compatibility with callers
      def normalized_changed_data(changed_data)
        normalize_changed_data(changed_data)
      end

      def audit_action_label(action)
        case action
        when "created"
          "Supporter created"
        when "updated"
          "Supporter updated"
        else
          action.to_s.humanize
        end
      end

      def duplicate_merge_audit_fields
        %w[email registered_voter self_reported_registered_voter registered_voter_status opt_in_email opt_in_text]
      end

      def apply_index_sort(scope)
        sort_by = ALLOWED_SORT_FIELDS.include?(params[:sort_by]) ? params[:sort_by] : "created_at"
        sort_dir = params[:sort_dir] == "asc" ? :asc : :desc
        sort_dir_sql = sort_dir == :asc ? "ASC" : "DESC"

        case sort_by
        when "village_name"
          scope.left_joins(:village).reorder(Arel.sql("villages.name #{sort_dir_sql}"), created_at: :desc)
        when "precinct_number"
          scope.left_joins(:precinct).reorder(Arel.sql("precincts.number #{sort_dir_sql}"), created_at: :desc)
        when "registered_voter"
          scope.reorder(
            Arel.sql("(CASE WHEN supporters.gec_voter_id IS NOT NULL OR supporters.verification_status = 'verified' THEN 2 WHEN supporters.registered_voter THEN 1 ELSE 0 END) #{sort_dir_sql}"),
            created_at: :desc
          )
        else
          scope.reorder(sort_by => sort_dir)
        end
      end
    end
  end
end
