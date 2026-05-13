# frozen_string_literal: true

module Api
  module V1
    class ReportsController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_reports_access!

      # GET /api/v1/reports/:report_type
      # Generate and download an Excel report.
      # Params:
      #   report_type: support_list | purge_list | transfer_list | referral_list | supporter_summary
      #   village_id (optional): filter to a specific village
      def show
        report_type = params[:report_type]
        report_filters = resolved_report_filters
        return if performed?

        unless ReportGenerator::REPORT_TYPES.include?(report_type)
          return render_api_error(
            message: "Unknown report type: #{report_type}. Valid types: #{ReportGenerator::REPORT_TYPES.join(', ')}",
            status: :unprocessable_entity,
            code: "invalid_report_type"
          )
        end

        unless allowed_report_types.include?(report_type)
          return render_api_error(
            message: "Report access denied for type: #{report_type}",
            status: :forbidden,
            code: "report_type_access_denied"
          )
        end

        generator = ReportGenerator.new(
          report_type: report_type,
          village_id: report_filters[:village_id],
          precinct_id: report_filters[:precinct_id],
          district_id: report_filters[:district_id],
          campaign_id: params[:campaign_id],
          registered_voter_status: params[:registered_voter_status],
          support_need: params[:support_need],
          registration_outreach_status: params[:registration_outreach_status] || params[:outreach_status],
          support_follow_up_status: params[:support_follow_up_status]
        )

        begin
          result = generator.generate
        rescue => e
          Rails.logger.error("Report generation failed: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
          return render_api_error(
            message: "Report generation failed: #{e.message}",
            status: :internal_server_error,
            code: "report_generation_failed"
          )
        end

        log_audit!(nil, action: "report_generated", changed_data: {
          "report_type" => report_type,
          "village_id" => report_filters[:village_id],
          "district_id" => report_filters[:district_id],
          "precinct_id" => report_filters[:precinct_id],
          "registered_voter_status" => params[:registered_voter_status],
          "support_need" => params[:support_need],
          "registration_outreach_status" => params[:registration_outreach_status] || params[:outreach_status],
          "support_follow_up_status" => params[:support_follow_up_status],
          "filename" => result[:filename]
        })

        send_data result[:package].to_stream.read,
          filename: result[:filename],
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          disposition: "attachment"
      end

      # GET /api/v1/reports/:report_type/preview
      def preview
        report_type = params[:report_type]
        report_filters = resolved_report_filters
        return if performed?

        unless ReportGenerator::REPORT_TYPES.include?(report_type)
          return render_api_error(
            message: "Unknown report type: #{report_type}. Valid types: #{ReportGenerator::REPORT_TYPES.join(', ')}",
            status: :unprocessable_entity,
            code: "invalid_report_type"
          )
        end

        unless allowed_report_types.include?(report_type)
          return render_api_error(
            message: "Report access denied for type: #{report_type}",
            status: :forbidden,
            code: "report_type_access_denied"
          )
        end

        generator = ReportGenerator.new(
          report_type: report_type,
          village_id: report_filters[:village_id],
          precinct_id: report_filters[:precinct_id],
          district_id: report_filters[:district_id],
          campaign_id: params[:campaign_id],
          preview_limit: (params[:limit] || 100).to_i.clamp(1, 250),
          registered_voter_status: params[:registered_voter_status],
          support_need: params[:support_need],
          registration_outreach_status: params[:registration_outreach_status] || params[:outreach_status],
          support_follow_up_status: params[:support_follow_up_status]
        )

        begin
          result = generator.preview
        rescue => e
          Rails.logger.error("Report preview failed: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
          return render_api_error(
            message: "Report preview failed: #{e.message}",
            status: :internal_server_error,
            code: "report_preview_failed"
          )
        end

        render json: result.merge(
          report_type: report_type,
          filters: {
            village_id: report_filters[:village_id],
            precinct_id: report_filters[:precinct_id],
            district_id: report_filters[:district_id],
            registered_voter_status: params[:registered_voter_status],
            support_need: params[:support_need],
            registration_outreach_status: params[:registration_outreach_status] || params[:outreach_status],
            support_follow_up_status: params[:support_follow_up_status]
          }
        )
      end

      # GET /api/v1/reports
      # List available report types with current counts
      def index
        available_report_types = allowed_report_types
        latest_gec = GecVoter.maximum(:gec_list_date)
        latest_import = GecImport.completed.latest.first
        village_changes = GecVoter.transferred
          .where.not(village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
          .where.not(previous_village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
        mapping_issues = GecVoter.transferred.where(village_name: GecImportService::UNASSIGNED_VILLAGE_NAME)
          .or(GecVoter.transferred.where(previous_village_name: GecImportService::UNASSIGNED_VILLAGE_NAME))
        supporter_scope = scoped_report_supporters
        quick_stats = {
          official_supporters: supporter_scope.count,
          matched_to_gec: supporter_scope.verified.count,
          total_verified: supporter_scope.verified.count,
          total_active: supporter_scope.count,
          public_signups: scope_supporters(Supporter.active.public_signups).count,
          unregistered: supporter_scope.where(registered_voter: false).count,
          referral_list_size: scope_supporters(Supporter.working_supporters.submitted_village_referrals).count,
          dpg_contacts_linked_to_gec: 0,
          dpg_contacts_unlinked_from_gec: 0,
          gec_voters_not_in_dpg: 0,
          possible_gec_matches: 0,
          transfer_list_size: 0,
          mapping_issues_list_size: 0,
          transfers: 0,
          purge_list_size: 0,
          latest_import_removed_voters: 0
        }

        if full_report_access?
          quick_stats.merge!(
            transfer_list_size: village_changes.count,
            mapping_issues_list_size: mapping_issues.count,
            transfers: village_changes.count,
            purge_list_size: GecVoter.where(status: "removed").count,
            latest_import_removed_voters: latest_import&.removed_records.to_i,
            dpg_contacts_linked_to_gec: scoped_cross_reference_contacts.where.not(gec_voter_id: nil).count,
            dpg_contacts_unlinked_from_gec: scoped_cross_reference_contacts.where(gec_voter_id: nil).count,
            possible_gec_matches: scoped_cross_reference_contacts.where(gec_voter_id: nil, verification_status: "flagged").count,
            gec_voters_not_in_dpg: scoped_cross_reference_gec_voters
              .where.not(id: Supporter.contacts.where.not(gec_voter_id: nil).select(:gec_voter_id))
              .count
          )
        end

        render json: {
          available_reports: available_report_types.map do |rt|
            {
              type: rt,
              name: report_name(rt),
              description: report_description(rt)
            }
          end,
          latest_gec_list_date: latest_gec,
          gec_data_loaded: GecVoter.active.any?,
          quick_stats: quick_stats
        }
      end

      private

      FULL_REPORT_TYPES = ReportGenerator::REPORT_TYPES
      COORDINATOR_REPORT_TYPES = %w[support_list referral_list supporter_summary].freeze

      def report_name(type)
        case type
        when "transfer_list"
          "Village Change List"
        when "mapping_issues_list"
          "Village Mapping Issues"
        when "dpg_contacts_linked_to_gec"
          "DPG Contacts Linked To GEC"
        when "dpg_contacts_unlinked_from_gec"
          "DPG Contacts Not Linked To GEC"
        when "gec_voters_not_in_dpg"
          "GEC Voters Not In DPG Contacts"
        when "possible_gec_matches"
          "Possible GEC Matches"
        else
          type.humanize.titleize
        end
      end

      def report_description(type)
        case type
        when "support_list"
          "All approved official supporters by village"
        when "purge_list"
          "Voters removed from GEC list (deceased or purged)"
        when "transfer_list"
          "GEC voters whose official village changed between list versions"
        when "referral_list"
          "Official supporters submitted by one village but currently assigned to another"
        when "mapping_issues_list"
          "GEC voters whose latest village could not be mapped cleanly to an official village"
        when "supporter_summary"
          "Per-village supporter summary with official totals and review status"
        when "dpg_contacts_linked_to_gec"
          "DPG contacts already linked to an official GEC voter record"
        when "dpg_contacts_unlinked_from_gec"
          "DPG contacts that still need a GEC voter link or registration follow-up"
        when "gec_voters_not_in_dpg"
          "Current public GEC voters without any linked DPG contact"
        when "possible_gec_matches"
          "Flagged DPG contacts with possible GEC matches for manual review"
        end
      end

      def allowed_report_types
        return FULL_REPORT_TYPES if full_report_access?
        return COORDINATOR_REPORT_TYPES if current_user&.coordinator?

        []
      end

      def full_report_access?
        current_user&.admin? || current_user&.data_team?
      end

      def scoped_report_supporters
        scope = scope_supporters(Supporter.working_supporters)
        if current_user&.coordinator? && current_user.assigned_district_id.present?
          scope = scope.joins(:village).where(villages: { district_id: current_user.assigned_district_id })
        end
        scope
      end

      def scoped_cross_reference_contacts
        scope_supporters(Supporter.contacts)
      end

      def scoped_cross_reference_gec_voters
        GecVoter.active
      end

      def resolved_report_filters
        village_id = params[:village_id].presence
        precinct_id = params[:precinct_id].presence
        district_id = params[:district_id].presence
        # Coordinators without an assigned district currently have campaign-wide
        # report access, which mirrors `compute_scoped_village_ids` returning nil.
        return { village_id: village_id, precinct_id: precinct_id, district_id: district_id } unless current_user&.coordinator?

        if current_user.assigned_district_id.present?
          if district_id.present? && district_id.to_i != current_user.assigned_district_id
            render_api_error(message: "District not in your assigned scope", status: :forbidden, code: "district_scope_denied")
            return {}
          end

          if village_id.present?
            village = Village.find_by(id: village_id)
            if village.blank? || village.district_id != current_user.assigned_district_id
              render_api_error(message: "Village not in your assigned scope", status: :forbidden, code: "village_scope_denied")
              return {}
            end
          end

          if precinct_id.present?
            precinct = Precinct.find_by(id: precinct_id)
            if precinct.blank? || precinct.village_id.blank? || !Village.where(id: precinct.village_id, district_id: current_user.assigned_district_id).exists?
              render_api_error(message: "Precinct not in your assigned scope", status: :forbidden, code: "precinct_scope_denied")
              return {}
            end
          end

          district_id ||= current_user.assigned_district_id
        end

        { village_id: village_id, precinct_id: precinct_id, district_id: district_id }
      end
    end
  end
end
