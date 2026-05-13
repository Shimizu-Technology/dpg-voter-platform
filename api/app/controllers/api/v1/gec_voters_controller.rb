# frozen_string_literal: true

module Api
  module V1
    class GecVotersController < ApplicationController
      include Authenticatable
      include AuditLoggable

      before_action :authenticate_request
      before_action :require_supporter_access!, only: [ :index, :stats, :households, :create_contact, :link_contact ]
      before_action :require_gec_upload_access!, only: [ :preview, :preview_status, :upload, :imports, :activate_import ]

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
        return { file_data: File.binread(file.tempfile.path) } unless S3Service.enabled?

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

      def import_json(import)
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
          metadata: import.metadata || {}
        }
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
