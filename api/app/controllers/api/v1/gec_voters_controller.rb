# frozen_string_literal: true

module Api
  module V1
    class GecVotersController < ApplicationController
      include Authenticatable
      include AuditLoggable

      before_action :authenticate_request
      before_action :require_supporter_access!, only: [ :index, :stats, :households, :create_contact, :link_contact ]
      before_action :require_gec_upload_access!, only: [
        :preview,
        :preview_status,
        :upload,
        :imports,
        :activate_import,
        :view_import_data,
        :view_import_changes,
        :view_import_skipped_rows,
        :preview_skipped_row_resolution,
        :resolve_skipped_row,
        :dismiss_skipped_row,
        :view_original,
        :download_import
      ]

      def index
        scope = scoped_gec_voters(GecVoter.active.includes(:village, :precinct))
        scope = apply_search(scope, params[:q]) if params[:q].present?
        scope = scope.where(village_id: params[:village_id]) if params[:village_id].present?
        scope = scope.where(precinct_id: params[:precinct_id]) if params[:precinct_id].present?
        scope = scope.where("LOWER(gec_voters.village_name) = ?", params[:village].to_s.downcase.strip) if params[:village].present?
        scope = scope.for_list_date(parsed_date(params[:list_date])) if params[:list_date].present?

        scope = scope.order(:village_name, :last_name, :first_name, :id)
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        per_page = [ [ params.fetch(:per_page, 50).to_i, 1 ].max, 200 ].min
        total = scope.count
        voters = scope.offset((page - 1) * per_page).limit(per_page).to_a
        linked_contact_counts = Supporter.contacts.where(gec_voter_id: voters.map(&:id)).group(:gec_voter_id).count

        render json: {
          gec_voters: voters.map { |voter| voter_json(voter, linked_contact_count: linked_contact_counts[voter.id].to_i) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      def stats
        scope = scoped_gec_voters(GecVoter.active)
        latest_import = GecImport.completed.latest.first
        village_counts = scope.group(:village_name).count.sort_by { |(_name, count)| -count }
        scoped_voter_ids = scope.select(:id)
        scoped_contacts = scope_supporters(Supporter.contacts)

        render json: {
          total_voters: scope.count,
          removed_voters: scoped_gec_voters(GecVoter.removed).count,
          transferred_voters: scope.transferred.count,
          latest_list_date: scope.maximum(:gec_list_date),
          latest_import: latest_import && import_json(latest_import),
          villages: village_counts.map { |name, count| { name: name, count: count } },
          linked_contacts: scoped_contacts.where(gec_voter_id: scoped_voter_ids).count
        }
      end

      def households
        query = params[:q].to_s.strip
        if query.blank? || query.length < 3
          return render_api_error(
            message: "Search at least 3 characters of an address",
            status: :unprocessable_entity,
            code: "address_query_too_short"
          )
        end

        voters = scoped_gec_voters(GecVoter.active.includes(:village, :precinct))
          .where("LOWER(gec_voters.address) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%")
          .order(:village_name, :address, :last_name, :first_name)
          .limit(250)
          .to_a
        linked_contact_counts = Supporter.contacts.where(gec_voter_id: voters.map(&:id)).group(:gec_voter_id).count

        contacts = scope_supporters(Supporter.contacts.includes(:village, :precinct, :gec_voter))
          .where("LOWER(supporters.street_address) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%")
          .order(:street_address, :last_name, :first_name)
          .limit(250)
          .to_a

        render json: {
          households: build_households(voters, contacts, linked_contact_counts: linked_contact_counts),
          voter_count: voters.length,
          contact_count: contacts.length
        }
      end

      def preview
        file = params[:file]
        return render_api_error(message: "No file uploaded", status: :unprocessable_entity, code: "missing_file") unless file.respond_to?(:tempfile)

        if pdf_file?(file)
          return render_api_error(message: "Uploaded PDF preview is empty", status: :unprocessable_entity, code: "empty_file") if File.zero?(file.tempfile.path)
          return render_api_error(message: "Uploaded PDF preview is too large (max 50 MB)", status: :unprocessable_entity, code: "file_too_large") if File.size(file.tempfile.path) > 50.megabytes

          preview_request_id = params[:preview_request_id].to_s.strip.presence || SecureRandom.uuid
          preview = GecPdfPreview.find_by(preview_request_id: preview_request_id, uploaded_by_user: current_user)
          unless preview
            preview = GecPdfPreview.create!(
              preview_request_id: preview_request_id,
              uploaded_by_user: current_user,
              filename: File.basename(file.original_filename.to_s.presence || "upload.pdf"),
              content_type: file.content_type.presence || "application/pdf",
              status: "pending",
              **pdf_preview_storage_attributes(file, preview_request_id)
            )
            GecPdfPreviewJob.perform_later(gec_pdf_preview_id: preview.id)
          end

          return render json: pdf_preview_json(preview), status: pdf_preview_response_status(preview)
        end

        service = GecImportService.new(
          file_path: file.tempfile.path,
          gec_list_date: parsed_date(params[:gec_list_date]) || Date.current,
          sheet_name: params[:sheet_name].presence
        )

        preview_data = service.preview(limit: [ params.fetch(:limit, 20).to_i, 100 ].min)
        render json: preview_data.merge(source_type: "spreadsheet")
      rescue StandardError => e
        render_api_error(message: "Failed to parse file: #{e.message}", status: :unprocessable_entity, code: "parse_error")
      end

      def preview_status
        preview_request_id = params[:preview_request_id].to_s.strip
        return render_api_error(message: "preview_request_id is required", status: :unprocessable_entity, code: "missing_preview_request_id") if preview_request_id.blank?

        preview = GecPdfPreview.find_by(preview_request_id: preview_request_id, uploaded_by_user: current_user)
        return render_api_error(message: "PDF preview not found", status: :not_found, code: "preview_not_found") unless preview

        render json: pdf_preview_json(preview), status: pdf_preview_response_status(preview)
      end

      def upload
        file = params[:file]
        return render_api_error(message: "No file uploaded", status: :unprocessable_entity, code: "missing_file") unless file.respond_to?(:tempfile)

        list_date = parsed_date(params[:gec_list_date])
        return render_api_error(message: "gec_list_date is required", status: :unprocessable_entity, code: "missing_list_date") unless list_date

        import_type = %w[full_list changes_only].include?(params[:import_type]) ? params[:import_type] : "full_list"
        if pdf_file?(file)
          confirm_review = ActiveModel::Type::Boolean.new.cast(params[:confirm_review])
          return render_api_error(message: "PDF preview is a sample. Confirm review before starting the background import.", status: :unprocessable_entity, code: "pdf_review_confirmation_required") unless confirm_review

          gec_import = GecImport.create!(
            gec_list_date: list_date,
            filename: "#{File.basename(file.original_filename.to_s.presence || "gec-list", ".*")}.csv",
            uploaded_by_user: current_user,
            import_type: import_type,
            status: "pending",
            metadata: {
              "stage" => "queued",
              "progress_percent" => 0,
              "mode" => "background",
              "source_type" => "pdf"
            }
          )
          upload_payload = GecImportUpload.create!(
            gec_import: gec_import,
            filename: File.basename(file.original_filename.to_s.presence || "gec-list.pdf"),
            content_type: file.content_type.presence || "application/pdf",
            file_data: File.binread(file.tempfile.path)
          )
          job = GecImportJob.perform_later(
            gec_import_id: gec_import.id,
            upload_id: upload_payload.id,
            gec_list_date: list_date.to_s,
            uploaded_by_user_id: current_user&.id,
            sheet_name: nil,
            import_type: import_type,
            confirm_review: confirm_review
          )
          gec_import.update_columns(
            metadata: (gec_import.metadata || {}).merge({
              "active_job_id" => job.job_id,
              "enqueued_at" => Time.current.iso8601
            })
          )
          return render json: {
            message: "GEC PDF import queued in background",
            async: true,
            import: import_json(gec_import)
          }, status: :accepted
        end

        service = GecImportService.new(
          file_path: file.tempfile.path,
          gec_list_date: list_date,
          uploaded_by_user: current_user,
          sheet_name: params[:sheet_name].presence,
          import_type: import_type
        )

        result = service.call
        if result.success
          log_audit!(result.gec_import, action: "gec_import", changed_data: result.stats)
          render json: {
            message: "GEC voter list imported successfully",
            import: import_json(result.gec_import),
            stats: result.stats,
            errors: result.errors.first(20)
          }, status: :created
        else
          render_api_error(message: "Import failed: #{result.errors.first}", status: :unprocessable_entity, code: "import_failed", details: result.errors.first(20))
        end
      end

      def imports
        imports = GecImport.includes(:uploaded_by_user).latest.limit(25)
        render json: {
          imports: imports.map { |import| import_json(import) }
        }
      end

      def activate_import
        gec_import = GecImport.find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import
        return render_api_error(message: "Only completed GEC imports can be activated", status: :unprocessable_entity, code: "import_not_completed") unless gec_import.status == "completed"

        previous_active_election_day = gec_import.active_election_day
        gec_import.activate_for_election!(actor_user: current_user)
        log_audit!(gec_import, action: "gec_import_activated", changed_data: { active_election_day: [ previous_active_election_day, true ] })
        render json: { import: import_json(gec_import.reload) }
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(message: e.record.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "activate_import_failed")
      end

      def view_import_data
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import

        unless gec_import.import_artifact_available?
          return render_api_error(message: "Parsed import data is not available for this import", status: :not_found, code: "parsed_data_not_available")
        end

        preview = build_existing_import_preview(
          gec_import,
          page: params.fetch(:page, 1).to_i,
          per_page: params.fetch(:per_page, 100).to_i,
          q: params[:q].to_s,
          village: params[:village].to_s
        )
        return render_api_error(message: "Could not load parsed import data", status: :service_unavailable, code: "artifact_unavailable") unless preview

        render json: {
          import: import_json(gec_import),
          preview: preview
        }
      end

      def view_import_changes
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import

        per_page = [ [ params.fetch(:per_page, 100).to_i, 1 ].max, 200 ].min
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        type = params[:type].to_s.presence || "all"
        q = params[:q].to_s.strip

        raw_counts = gec_import.change_records.group(:change_type).count
        routed_rows = import_routed_to_unassigned_rows(gec_import)
        routed_rows = apply_routed_to_unassigned_search_filter(routed_rows, q) if q.present? && type == "routed_to_unassigned"

        if type == "routed_to_unassigned"
          total_rows = routed_rows.length
          total_pages = total_rows.zero? ? 1 : (total_rows.to_f / per_page).ceil
          page = [ page, total_pages ].min
          rows = routed_rows.slice((page - 1) * per_page, per_page) || []
          changes = rows
        else
          scope = gec_import.change_records.latest_first
          scope = apply_change_type_filter(scope, type)
          scope = apply_change_search_filter(scope, q) if q.present?

          total_rows = scope.count
          total_pages = total_rows.zero? ? 1 : (total_rows.to_f / per_page).ceil
          page = [ page, total_pages ].min
          rows = scope.offset((page - 1) * per_page).limit(per_page)
          changes = rows.map { |row| import_change_json(row) }
        end

        render json: {
          import: import_json(gec_import),
          changes: changes,
          counts: {
            all: raw_counts.values.sum,
            new: raw_counts["new"].to_i,
            changed: raw_counts["updated"].to_i + raw_counts["transferred"].to_i,
            updated: raw_counts["updated"].to_i,
            removed: raw_counts["removed"].to_i,
            transferred: raw_counts["transferred"].to_i,
            routed_to_unassigned: gec_import.metadata["unassigned"].to_i
          },
          filters: { type: type, q: q },
          pagination: {
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            total_rows: total_rows
          }
        }
      end

      def view_import_skipped_rows
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import

        per_page = [ [ params.fetch(:per_page, 25).to_i, 1 ].max, 100 ].min
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        status = params[:status].to_s.presence || "all"
        q = params[:q].to_s.strip

        scope = gec_import.skipped_rows.latest_first
        scope = apply_skipped_row_status_filter(scope, status)
        scope = apply_skipped_row_search_filter(scope, q) if q.present?

        total_rows = scope.count
        total_pages = total_rows.zero? ? 1 : (total_rows.to_f / per_page).ceil
        page = [ page, total_pages ].min
        rows = scope.offset((page - 1) * per_page).limit(per_page)
        raw_counts = gec_import.skipped_rows.group(:resolution_status).count

        render json: {
          import: import_json(gec_import),
          skipped_rows: rows.map { |row| import_skipped_row_json(row) },
          counts: {
            all: raw_counts.values.sum,
            pending: raw_counts["pending"].to_i,
            resolved: raw_counts["resolved_created"].to_i + raw_counts["resolved_updated"].to_i,
            dismissed: raw_counts["dismissed"].to_i
          },
          filters: { status: status, q: q },
          pagination: {
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            total_rows: total_rows
          }
        }
      end

      def preview_skipped_row_resolution
        skipped_row = find_import_skipped_row
        return unless skipped_row

        result = skipped_row_resolution_service(skipped_row).preview
        render json: {
          skipped_row: import_skipped_row_json(skipped_row),
          preview: skipped_row_resolution_json(result)
        }
      end

      def resolve_skipped_row
        skipped_row = find_import_skipped_row
        return unless skipped_row

        result = skipped_row_resolution_service(skipped_row).apply!
        unless result.success
          return render_api_error(
            message: result.errors.first || "Could not resolve skipped row",
            status: :unprocessable_entity,
            code: "skipped_row_resolution_failed",
            details: skipped_row_resolution_json(result)
          )
        end

        render json: {
          message: "Skipped row resolved successfully",
          skipped_row: import_skipped_row_json(result.skipped_row),
          preview: skipped_row_resolution_json(result)
        }
      end

      def dismiss_skipped_row
        skipped_row = find_import_skipped_row
        return unless skipped_row

        result = skipped_row_resolution_service(skipped_row).dismiss!
        unless result.success
          return render_api_error(
            message: result.errors.first || "Could not dismiss skipped row",
            status: :unprocessable_entity,
            code: "skipped_row_dismiss_failed",
            details: skipped_row_resolution_json(result)
          )
        end

        render json: {
          message: "Skipped row dismissed",
          skipped_row: import_skipped_row_json(result.skipped_row)
        }
      end

      def view_original
        gec_import = GecImport.find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import

        unless gec_import.raw_source_available?
          return render_api_error(message: "Original uploaded file is not available for this import", status: :not_found, code: "file_not_available")
        end

        filename = gec_import.raw_source_filename || gec_import.filename || "gec_import_#{gec_import.id}"
        content_type = gec_import.raw_content_type.presence || "application/octet-stream"
        view_url = S3Service.presigned_url(
          gec_import.raw_file_s3_key,
          expires_in: 1800,
          filename: filename,
          disposition: :inline
        )
        return render_api_error(message: "Could not generate original file link", status: :service_unavailable, code: "s3_error") unless view_url

        render json: {
          view_url: view_url,
          filename: filename,
          content_type: content_type,
          inline_supported: content_type.include?("pdf")
        }
      end

      def download_import
        gec_import = GecImport.find_by(id: params[:id])
        return render_api_error(message: "Import not found", status: :not_found, code: "not_found") unless gec_import

        unless gec_import.downloadable_file_available?
          return render_api_error(message: "Download file is not available for this import", status: :not_found, code: "file_not_available")
        end

        download_url = S3Service.presigned_url(
          gec_import.downloadable_file_key,
          expires_in: 300,
          filename: gec_import.downloadable_filename,
          disposition: :attachment
        )
        return render_api_error(message: "Could not generate download link", status: :service_unavailable, code: "s3_error") unless download_url

        render json: {
          download_url: download_url,
          filename: gec_import.downloadable_filename || "gec_import_#{gec_import.id}"
        }
      end

      def create_contact
        voter = scoped_gec_voters(GecVoter.active).find_by(id: params[:id])
        return render_api_error(message: "GEC voter not found", status: :not_found, code: "not_found") unless voter

        contact = nil
        ActiveRecord::Base.transaction do
          contact = Supporter.create!(
            first_name: voter.first_name,
            middle_name: voter.middle_name,
            last_name: voter.last_name,
            village: voter.village || Village.find_by(name: voter.village_name) || Village.find_or_create_by!(name: GecImportService::UNASSIGNED_VILLAGE_NAME),
            precinct: voter.precinct,
            street_address: voter.address,
            dob: voter.dob,
            source: "staff_entry",
            attribution_method: "staff_manual",
            contact_classification: params[:contact_classification].presence_in(Supporter::CONTACT_CLASSIFICATIONS) || "active_contact",
            entered_by: current_user,
            registered_voter: true,
            self_reported_registered_voter: true,
            registered_voter_status: "yes",
            status: "active"
          )
          contact.update!(
            gec_voter: voter,
            precinct: voter.precinct || contact.precinct,
            verification_status: "verified",
            verification_reason: "matched_current_gec",
            verified_at: Time.current,
            verified_by: current_user
          )

          log_audit!(contact, action: "created_from_gec_voter", changed_data: { gec_voter_id: voter.id })
        end
        render json: { supporter: supporter_json(contact), gec_voter: voter_json(voter) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(message: e.record.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "contact_create_failed")
      end

      def link_contact
        voter = scoped_gec_voters(GecVoter.active).find_by(id: params[:id])
        return render_api_error(message: "GEC voter not found", status: :not_found, code: "not_found") unless voter

        contact = scope_supporters(Supporter.contacts).find_by(id: params[:supporter_id])
        return render_api_error(message: "Contact not found", status: :not_found, code: "contact_not_found") unless contact

        previous_gec_voter_id = contact.gec_voter_id
        contact.update!(
          gec_voter: voter,
          village: voter.village || contact.village,
          precinct: voter.precinct || contact.precinct,
          registered_voter: true,
          registered_voter_status: "yes",
          verification_status: "verified",
          verification_reason: "matched_current_gec",
          verified_at: Time.current,
          verified_by: current_user
        )

        log_audit!(contact, action: "linked_to_gec_voter", changed_data: { gec_voter_id: [ previous_gec_voter_id, voter.id ] })
        render json: { supporter: supporter_json(contact), gec_voter: voter_json(voter) }
      rescue ActiveRecord::RecordInvalid => e
        render_api_error(message: e.record.errors.full_messages.to_sentence, status: :unprocessable_entity, code: "contact_link_failed")
      end

      private

      def require_gec_upload_access!
        return if can_upload_gec?

        render_api_error(message: "GEC import access required", status: :forbidden, code: "gec_import_access_required")
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def pdf_file?(file)
        filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : ""
        content_type = file.respond_to?(:content_type) ? file.content_type.to_s : ""

        filename.downcase.end_with?(".pdf") || content_type.include?("pdf")
      end

      def pdf_preview_storage_attributes(file, preview_request_id)
        return { file_data: File.binread(file.tempfile.path) } if Rails.env.development? || !S3Service.enabled?

        filename = File.basename(file.original_filename.to_s.presence || "upload.pdf")
        safe_filename = S3Service.safe_filename(filename, fallback: "preview.pdf")
        s3_key = "gec-pdf-previews/#{preview_request_id}/source/#{safe_filename}"
        uploaded = File.open(file.tempfile.path, "rb") do |io|
          S3Service.upload(s3_key, io, content_type: file.content_type.presence || "application/pdf")
        end
        raise "Could not store PDF preview upload" unless uploaded

        { file_s3_key: s3_key }
      end

      def pdf_preview_json(preview)
        result_data = preview.result_data.is_a?(Hash) ? preview.result_data : {}
        json = {
          async: true,
          source_type: "pdf",
          preview_request_id: preview.preview_request_id,
          status: preview.status
        }
        if preview.completed?
          json.merge!(
            qa: result_data["qa"] || {},
            warnings: result_data["warnings"] || [],
            row_count: result_data["row_count"].to_i,
            preview_rows: Array(result_data["preview_rows"])
          )
        elsif preview.failed?
          json[:error] = preview.error_message.presence || "PDF preview failed"
        end
        json
      end

      def pdf_preview_response_status(preview)
        preview.completed? || preview.failed? ? :ok : :accepted
      end

      def scoped_gec_voters(scope)
        ids = scoped_village_ids
        ids ? scope.where(village_id: ids) : scope
      end

      def apply_search(scope, query)
        terms = query.to_s.downcase.strip.split(/\s+/).first(6)
        return scope if terms.empty?

        terms.reduce(scope) do |memo, term|
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
          memo.where(
            <<~SQL.squish,
              LOWER(gec_voters.first_name) LIKE :pattern
              OR LOWER(gec_voters.middle_name) LIKE :pattern
              OR LOWER(gec_voters.last_name) LIKE :pattern
              OR LOWER(gec_voters.address) LIKE :pattern
              OR LOWER(gec_voters.village_name) LIKE :pattern
              OR LOWER(gec_voters.precinct_number) LIKE :pattern
              OR LOWER(gec_voters.voter_registration_number) LIKE :pattern
            SQL
            pattern: pattern
          )
        end
      end

      def build_households(voters, contacts, linked_contact_counts: {})
        grouped = {}

        voters.each do |voter|
          key = household_key(voter.address, voter.village_name)
          next if key.blank?

          grouped[key] ||= household_json(voter.address, voter.village_name)
          grouped[key][:gec_voters] << voter_json(voter, linked_contact_count: linked_contact_counts[voter.id].to_i)
        end

        contacts.each do |contact|
          key = household_key(contact.street_address, contact.village&.name)
          next if key.blank?

          grouped[key] ||= household_json(contact.street_address, contact.village&.name)
          grouped[key][:contacts] << supporter_json(contact)
        end

        grouped.values.sort_by { |row| [ row[:village_name].to_s, row[:address].to_s ] }
      end

      def household_key(address, village_name)
        normalized_address = address.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
        return nil if normalized_address.blank?

        "#{village_name.to_s.downcase.strip}|#{normalized_address}"
      end

      def household_json(address, village_name)
        {
          address: address,
          village_name: village_name,
          gec_voters: [],
          contacts: []
        }
      end

      def import_json(import, skipped_counts_by_import: nil)
        counts_for_import = if skipped_counts_by_import
          skipped_counts_by_import.each_with_object(Hash.new(0)) do |((import_id, status), count), memo|
            memo[status] = count if import_id == import.id
          end
        else
          import.skipped_rows.group(:resolution_status).count
        end

        {
          id: import.id,
          gec_list_date: import.gec_list_date,
          filename: import.filename,
          total_records: import.total_records,
          new_records: import.new_records,
          updated_records: import.updated_records,
          removed_records: import.removed_records,
          transferred_records: import.transferred_records,
          re_vetted_count: import.re_vetted_count,
          ambiguous_dob_count: import.ambiguous_dob_count,
          import_type: import.import_type,
          status: import.status,
          active_election_day: import.active_election_day,
          created_at: import.created_at,
          uploaded_by_email: import.uploaded_by_user&.email,
          has_import_artifact: import.import_artifact_available?,
          has_original_file: import.raw_source_available?,
          has_downloadable_file: import.downloadable_file_available?,
          raw_filename: import.raw_filename,
          original_filename: import.original_filename,
          raw_content_type: import.raw_content_type,
          original_content_type: import.original_content_type,
          skipped_rows_count: counts_for_import.values.sum,
          pending_skipped_rows_count: counts_for_import["pending"].to_i,
          metadata: import.metadata || {}
        }
      end

      def import_change_json(change)
        {
          id: change.id,
          change_type: change.change_type,
          row_number: change.row_number,
          first_name: change.first_name,
          middle_name: change.respond_to?(:middle_name) ? change.middle_name : nil,
          last_name: change.last_name,
          voter_registration_number: change.voter_registration_number,
          village_name: change.village_name,
          previous_village_name: change.previous_village_name,
          birth_year: change.birth_year,
          dob: change.dob,
          details: change.details || {}
        }
      end

      def import_skipped_row_json(skipped_row)
        {
          id: skipped_row.id,
          row_number: skipped_row.row_number,
          message: skipped_row.message,
          source_name: skipped_row.source_name,
          first_name: skipped_row.first_name,
          middle_name: skipped_row.respond_to?(:middle_name) ? skipped_row.middle_name : nil,
          last_name: skipped_row.last_name,
          voter_registration_number: skipped_row.voter_registration_number,
          village_name: skipped_row.village_name,
          birth_year: skipped_row.birth_year,
          dob: skipped_row.dob,
          raw_values: skipped_row.raw_values || [],
          resolution_status: skipped_row.resolution_status,
          resolution_action: skipped_row.resolution_action,
          corrected_values: skipped_row.corrected_values || {},
          resolution_details: skipped_row.resolution_details || {},
          resolved_at: skipped_row.resolved_at,
          resolved_by_email: skipped_row.resolved_by_user&.email,
          resolved_gec_voter: skipped_row.resolved_gec_voter&.as_json(
            only: [ :id, :first_name, :middle_name, :last_name, :village_name, :voter_registration_number, :birth_year, :dob ]
          )
        }
      end

      def skipped_row_resolution_json(result)
        {
          status: result.status,
          errors: result.errors || [],
          suggested_action: result.suggested_action,
          corrected_values: result.corrected_values || {},
          target_voter: result.target_voter&.as_json(only: [ :id, :first_name, :middle_name, :last_name, :village_name, :voter_registration_number, :birth_year, :dob ]),
          candidate_matches: Array(result.candidate_matches).map do |entry|
            {
              confidence: entry[:confidence],
              match_type: entry[:match_type],
              match_count: entry[:match_count],
              gec_voter: entry[:gec_voter].as_json(only: [ :id, :first_name, :middle_name, :last_name, :village_name, :voter_registration_number, :birth_year, :dob ])
            }
          end
        }
      end

      def import_routed_to_unassigned_rows(gec_import)
        dataset = fetch_cached_import_viewer_dataset(gec_import)
        return [] unless dataset.is_a?(Hash)

        rows = Array(dataset["rows"])
        source_type = dataset["source_type"].to_s

        rows.each_with_index.filter_map do |row, index|
          next unless ActiveModel::Type::Boolean.new.cast(row["routed_to_unassigned"])

          source_village = routed_to_unassigned_source_village(row, source_type)
          {
            id: "routed-to-unassigned-#{index + 1}",
            change_type: "routed_to_unassigned",
            row_number: index + 2,
            first_name: row["first_name"],
            middle_name: row["middle_name"],
            last_name: row["last_name"],
            voter_registration_number: row["voter_registration_number"],
            village_name: GecImportService::UNASSIGNED_VILLAGE_NAME,
            previous_village_name: source_village,
            birth_year: row["birth_year"],
            dob: row["dob"],
            details: {
              source_name: routed_to_unassigned_source_name(row),
              source_village_name: source_village,
              reason: "The importer could not safely match this row to a canonical Guam village, so it was routed to Unassigned for review transparency.",
              changed_fields: {
                village_name: {
                  before: source_village.presence,
                  after: GecImportService::UNASSIGNED_VILLAGE_NAME
                }
              }
            }
          }
        end.reverse
      end

      def routed_to_unassigned_source_village(row, source_type)
        field = source_type == "pdf" ? "source_village" : "source_village_name"
        row[field].presence
      end

      def routed_to_unassigned_source_name(row)
        row["name"].presence || NameParser.combine(
          first_name: row["first_name"],
          middle_name: row["middle_name"],
          last_name: row["last_name"],
          format: :last_comma_first
        )
      end

      def apply_change_type_filter(scope, type)
        case type
        when "new", "updated", "removed", "transferred"
          scope.where(change_type: type)
        when "changed"
          scope.where(change_type: %w[updated transferred])
        else
          scope
        end
      end

      def apply_change_search_filter(scope, query)
        like = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope.where(
          "LOWER(first_name) LIKE :q OR LOWER(last_name) LIKE :q OR LOWER(village_name) LIKE :q OR LOWER(COALESCE(previous_village_name, '')) LIKE :q OR LOWER(COALESCE(voter_registration_number, '')) LIKE :q",
          q: like
        )
      end

      def apply_routed_to_unassigned_search_filter(rows, query)
        needle = query.downcase
        rows.select do |row|
          [
            row[:first_name],
            row[:middle_name],
            row[:last_name],
            row[:voter_registration_number],
            row[:birth_year],
            row[:village_name],
            row[:previous_village_name],
            row.dig(:details, :source_name),
            row.dig(:details, :source_village_name)
          ].any? { |value| value.to_s.downcase.include?(needle) }
        end
      end

      def apply_skipped_row_status_filter(scope, status)
        case status
        when "pending"
          scope.where(resolution_status: "pending")
        when "resolved"
          scope.where(resolution_status: %w[resolved_created resolved_updated])
        when "dismissed"
          scope.where(resolution_status: "dismissed")
        else
          scope
        end
      end

      def apply_skipped_row_search_filter(scope, query)
        like = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope.where(
          "LOWER(COALESCE(first_name, '')) LIKE :q OR LOWER(COALESCE(last_name, '')) LIKE :q OR LOWER(COALESCE(village_name, '')) LIKE :q OR LOWER(COALESCE(voter_registration_number, '')) LIKE :q OR LOWER(COALESCE(source_name, '')) LIKE :q",
          q: like
        )
      end

      def find_import_skipped_row
        skipped_row = GecImportSkippedRow.includes(:resolved_by_user, :resolved_gec_voter).find_by(id: params[:skipped_row_id], gec_import_id: params[:id])
        return skipped_row if skipped_row

        render_api_error(message: "Skipped row not found", status: :not_found, code: "not_found")
        nil
      end

      def skipped_row_resolution_service(skipped_row)
        GecImportSkippedRowResolutionService.new(
          skipped_row: skipped_row,
          actor_user: current_user,
          attributes: skipped_row_resolution_params.to_h,
          selected_gec_voter_id: params[:selected_gec_voter_id]
        )
      end

      def skipped_row_resolution_params
        params.fetch(:corrected_values, ActionController::Parameters.new).permit(:first_name, :middle_name, :last_name, :village_name, :voter_registration_number, :birth_year, :dob)
      end

      def build_existing_import_preview(gec_import, page:, per_page:, q:, village:)
        dataset = fetch_cached_import_viewer_dataset(gec_import)
        return nil unless dataset

        filtered_rows = apply_import_view_filters(
          rows: dataset["rows"] || [],
          source_type: dataset["source_type"],
          q: q,
          village: village
        )

        normalized_per_page = [ [ per_page.to_i, 1 ].max, 250 ].min
        total_rows = filtered_rows.length
        total_pages = total_rows.zero? ? 1 : (total_rows.to_f / normalized_per_page).ceil
        effective_page = [ [ page.to_i, 1 ].max, total_pages ].min
        page_rows = filtered_rows.slice((effective_page - 1) * normalized_per_page, normalized_per_page) || []

        {
          source_type: dataset["source_type"],
          sheets: dataset["sheets"],
          headers: dataset["headers"],
          column_map: dataset["column_map"],
          row_count: dataset["row_count"],
          qa: dataset["qa"],
          warnings: dataset["warnings"] || [],
          available_villages: dataset["available_villages"] || [],
          pagination: {
            page: effective_page,
            per_page: normalized_per_page,
            total_pages: total_pages,
            total_rows: total_rows
          },
          preview_rows: page_rows
        }
      rescue StandardError => e
        Rails.logger.warn("GecVotersController import #{gec_import.id}: preview build failed: #{e.class}: #{e.message}")
        nil
      end

      def fetch_cached_import_viewer_dataset(gec_import)
        cache_key = import_viewer_cache_key(gec_import)
        cached = Rails.cache.read(cache_key)
        return cached if cached.is_a?(Hash) && cached["rows"].is_a?(Array)

        dataset = build_import_viewer_dataset(gec_import)
        return nil unless dataset

        if dataset_cacheable?(dataset)
          Rails.cache.write(cache_key, dataset, expires_in: 6.hours)
        else
          Rails.logger.info(
            "GecVotersController import #{gec_import.id}: skipped viewer dataset cache " \
            "(rows=#{dataset["row_count"]}, cache_row_limit=#{import_viewer_cache_row_limit})"
          )
        end
        dataset
      rescue StandardError => e
        Rails.logger.warn("GecVotersController import #{gec_import.id}: viewer cache failed: #{e.class}: #{e.message}")
        nil
      end

      def import_viewer_cache_key(gec_import)
        artifact_version = gec_import.original_file_s3_key.to_s
        "dpg_gec_import_viewer:v1:#{gec_import.id}:#{Digest::SHA256.hexdigest(artifact_version)}"
      end

      def import_viewer_cache_row_limit
        100_000
      end

      def dataset_cacheable?(dataset)
        dataset["row_count"].to_i <= import_viewer_cache_row_limit
      end

      def build_import_viewer_dataset(gec_import)
        artifact_data = S3Service.download(gec_import.original_file_s3_key)
        return nil unless artifact_data

        filename = gec_import.original_filename.presence || gec_import.filename
        extension = File.extname(filename).downcase
        extension = ".csv" unless %w[.csv .xlsx .xls].include?(extension)

        temp = Tempfile.new([ "gec_import_preview", extension ])
        temp.binmode
        temp.write(artifact_data)
        temp.flush

        service = GecImportService.new(file_path: temp.path, gec_list_date: gec_import.gec_list_date)
        preview_data = service.preview_all

        if gec_import.imported_from_pdf?
          rows = preview_data[:preview_rows].map do |row|
            routed_to_unassigned = row[:village_name].blank?
            {
              "name" => NameParser.combine(
                first_name: row[:first_name],
                middle_name: row[:middle_name],
                last_name: row[:last_name],
                format: :last_comma_first
              ),
              "first_name" => row[:first_name],
              "middle_name" => row[:middle_name],
              "last_name" => row[:last_name],
              "address" => row[:address],
              "village" => row[:village_name].presence || GecImportService::UNASSIGNED_VILLAGE_NAME,
              "source_village" => row[:village_name],
              "precinct_number" => row[:precinct_number],
              "birth_year" => row[:birth_year],
              "voter_registration_number" => row[:voter_registration_number],
              "routed_to_unassigned" => routed_to_unassigned
            }
          end

          {
            "source_type" => "pdf",
            "qa" => gec_import.metadata["pdf_qa"] || {},
            "warnings" => Array(gec_import.metadata["pdf_warnings"]).first(20),
            "row_count" => preview_data[:row_count],
            "rows" => rows,
            "available_villages" => rows.map { |row| row["village"] }.compact.uniq.sort
          }
        else
          rows = preview_data[:preview_rows].map do |row|
            normalized_row = row.stringify_keys
            source_village = normalized_row["village_name"].presence || normalized_row["village"].presence
            routed_to_unassigned = source_village.blank?

            normalized_row.merge(
              "source_village_name" => source_village,
              "village_name" => source_village.presence || GecImportService::UNASSIGNED_VILLAGE_NAME,
              "routed_to_unassigned" => routed_to_unassigned
            )
          end

          {
            "source_type" => "spreadsheet",
            "sheets" => preview_data[:sheets],
            "headers" => preview_data[:headers],
            "column_map" => preview_data[:column_map],
            "row_count" => preview_data[:row_count],
            "rows" => rows,
            "available_villages" => rows.map { |row| row["village_name"] || row["village"] }.compact.uniq.sort
          }
        end
      ensure
        temp&.close!
      end

      def apply_import_view_filters(rows:, source_type:, q:, village:)
        filtered = rows

        if village.present?
          village_field = source_type == "pdf" ? "village" : "village_name"
          filtered = filtered.select { |row| row[village_field].to_s.casecmp?(village.strip) }
        end

        if q.present?
          query = q.downcase.strip
          searchable_fields = if source_type == "pdf"
            %w[name village precinct_number birth_year voter_registration_number]
          else
            %w[first_name middle_name last_name village_name village precinct_number birth_year dob voter_registration_number]
          end
          filtered = filtered.select do |row|
            searchable_fields.any? { |field| row[field].to_s.downcase.include?(query) }
          end
        end

        filtered
      end

      def voter_json(voter, linked_contact_count: nil)
        voter.as_json(
          only: [
            :id, :first_name, :middle_name, :last_name, :dob, :birth_year, :address,
            :village_name, :village_id, :precinct_id, :precinct_number,
            :previous_village_name, :voter_registration_number, :status,
            :dob_ambiguous, :gec_list_date
          ]
        ).merge(
          precinct_label: voter.precinct&.number,
          linked_contact_count: linked_contact_count || Supporter.contacts.where(gec_voter_id: voter.id).count
        )
      end

      def supporter_json(contact)
        {
          id: contact.id,
          first_name: contact.first_name,
          middle_name: contact.middle_name,
          last_name: contact.last_name,
          print_name: contact.print_name,
          contact_number: contact.contact_number,
          email: contact.email,
          street_address: contact.street_address,
          village_id: contact.village_id,
          village_name: contact.village&.name,
          precinct_id: contact.precinct_id,
          precinct_number: contact.precinct&.number,
          contact_classification: contact.contact_classification,
          current_gec_match: contact.gec_voter_id.present?,
          gec_voter_id: contact.gec_voter_id
        }
      end
    end
  end
end
