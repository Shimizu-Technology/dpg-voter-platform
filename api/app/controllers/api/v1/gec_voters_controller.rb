# frozen_string_literal: true

require "digest"
require "securerandom"

module Api
  module V1
    class GecVotersController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_data_ops_access!

      # GET /api/v1/gec_voters
      # List GEC voters with optional filters
      def index
        scope = ActiveModel::Type::Boolean.new.cast(params[:election_day_only]) ? GecVoter.election_day_active : GecVoter.active

        if params[:q].present?
          scope = apply_loose_search(scope, params[:q])
        end

        scope = scope.where(village_id: params[:village_id]) if params[:village_id].present?
        scope = scope.where("LOWER(village_name) = ?", params[:village].downcase.strip) if params[:village].present?
        scope = scope.where("LOWER(last_name) LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(params[:last_name].downcase.strip)}%") if params[:last_name].present?
        scope = scope.where("LOWER(first_name) LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(params[:first_name].downcase.strip)}%") if params[:first_name].present?

        if params[:list_date].present?
          list_date = Date.parse(params[:list_date]) rescue nil
          return render_api_error(message: "Invalid date format for list_date", status: :unprocessable_entity, code: "invalid_date") unless list_date
          scope = scope.for_list_date(list_date)
        end

        scope = scope.order(:village_name, :last_name, :first_name)

        # Paginate
        page = (params[:page] || 1).to_i
        per_page = [ (params[:per_page] || 50).to_i, 200 ].min
        total = scope.count
        voters = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          gec_voters: voters.as_json(only: [ :id, :first_name, :middle_name, :last_name, :dob, :birth_year, :address, :village_name, :village_id, :precinct_id, :precinct_number, :previous_village_name, :voter_registration_number, :status, :dob_ambiguous, :gec_list_date ]),
          pagination: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }
        }
      end

      # GET /api/v1/gec_voters/stats
      # Overview stats about the current GEC voter list
      def stats
        election_day_import = GecImport.active_election_day_import
        latest_date = GecVoter.active.maximum(:gec_list_date)
        latest_import = GecImport.completed.latest.first

        village_counts = GecVoter.active.includes(:village).each_with_object(Hash.new(0)) do |voter, counts|
          name = voter.village&.name || GecImportService.normalize_village_name(voter.village_name, allow_unknown: false) || GecImportService::UNASSIGNED_VILLAGE_NAME
          counts[name] += 1 if name.present?
        end.sort_by { |(_name, count)| -count }
        unassigned_name = GecImportService::UNASSIGNED_VILLAGE_NAME
        official_village_count = village_counts.count { |(name, _count)| name != unassigned_name }
        unassigned_gec_voters = village_counts.find { |(name, _count)| name == unassigned_name }&.last.to_i

        render json: {
          total_voters: GecVoter.active.count,
          removed_voters: GecVoter.removed.count,
          transferred_voters: GecVoter.transferred.count,
          latest_list_date: latest_date,
          election_day_list_date: GecVoter.election_day_list_date,
          active_election_day_import: election_day_import && import_json(election_day_import),
          latest_import: latest_import&.as_json(only: [ :id, :gec_list_date, :filename, :total_records, :new_records, :updated_records, :removed_records, :transferred_records, :re_vetted_count, :ambiguous_dob_count, :import_type, :status, :created_at ]),
          villages: village_counts.map { |name, count| { name: name, count: count } },
          official_village_count: official_village_count,
          unassigned_gec_voters: unassigned_gec_voters,
          ambiguous_dob_count: GecVoter.active.with_ambiguous_dob.count,
          last_change_summary: latest_import&.change_summary
        }
      end

      # POST /api/v1/gec_voters/upload
      # Upload a new GEC voter list (Excel/CSV, or PDF with parser + QA gate)
      def upload
        file = params[:file]
        unless file.respond_to?(:tempfile)
          return render_api_error(
            message: "No file uploaded",
            status: :unprocessable_entity,
            code: "missing_file"
          )
        end

        unless params[:gec_list_date].present?
          return render_api_error(
            message: "gec_list_date is required (YYYY-MM-DD)",
            status: :unprocessable_entity,
            code: "missing_list_date"
          )
        end

        gec_list_date = Date.parse(params[:gec_list_date]) rescue nil
        return render_api_error(message: "Invalid date format for gec_list_date", status: :unprocessable_entity, code: "invalid_date") unless gec_list_date
        sheet_name = requested_sheet_name(file)

        import_type = %w[full_list changes_only].include?(params[:import_type]) ? params[:import_type] : "full_list"

        import_file_path = file.tempfile.path
        pdf_qa = nil
        pdf_warnings = []
        csv_tempfile = nil
        async_import = params[:async_import].nil? ? true : ActiveModel::Type::Boolean.new.cast(params[:async_import])

        begin
          confirm_review = ActiveModel::Type::Boolean.new.cast(params[:confirm_review])

          if pdf_file?(file) && !async_import
            parser = GecPdfParserService.new(file_path: file.tempfile.path)
            # Always do a full parse on upload (we need the rows to write the CSV).
            # The cache is only used for QA gate validation — if it matches, we skip
            # re-validating QA and trust the already-approved preview result.
            expected_cache_key = build_pdf_parse_cache_key(file.tempfile.path)
            requested_cache_key = params[:parse_cache_key].presence
            cache_key = requested_cache_key == expected_cache_key ? requested_cache_key : nil
            cached_qa = read_cached_pdf_parse(cache_key)
            parsed = parser.parse

            if parsed.errors.any?
              return render_api_error(
                message: "PDF parsing failed: #{parsed.errors.first}",
                status: :unprocessable_entity,
                code: "pdf_parse_failed",
                details: parsed.errors.first(10)
              )
            end

            # Prefer preview-approved QA when cache key matches, but sanity-check fresh parse.
            fresh_qa = parsed.qa || {}
            cached_pdf_qa = cached_qa&.qa.presence
            pdf_qa = cached_pdf_qa || fresh_qa
            pdf_warnings = parsed.warnings

            if cached_pdf_qa.present?
              cached_rows = cached_pdf_qa[:row_count].to_i
              fresh_rows = fresh_qa[:row_count].to_i

              if cached_rows.positive? && fresh_rows < (cached_rows * 0.95).to_i
                return render_api_error(
                  message: "PDF row count changed significantly since preview (#{fresh_rows} vs #{cached_rows}). Re-preview before importing.",
                  status: :unprocessable_entity,
                  code: "pdf_row_count_mismatch"
                )
              end
            end

            if pdf_qa[:status] == "fail" || fresh_qa[:status] == "fail"
              return render_api_error(
                message: "PDF QA failed. Please review parsing quality before importing.",
                status: :unprocessable_entity,
                code: "pdf_quality_failed",
                details: parsed.warnings
              )
            end

            review_status = (pdf_qa[:status] == "review") || (fresh_qa[:status] == "review")

            if review_status && !confirm_review
              return render_api_error(
                message: "PDF QA is in review status. Confirm review before importing.",
                status: :unprocessable_entity,
                code: "pdf_quality_review_required",
                details: parsed.warnings
              )
            end

            csv_tempfile = parser.write_normalized_csv(parsed.rows)
            import_file_path = csv_tempfile.path
          end

          if async_import
            if pdf_file?(file) && !confirm_review
              return render_api_error(
                message: "PDF preview is only a sample. Confirm review before starting the background import.",
                status: :unprocessable_entity,
                code: "pdf_review_confirmation_required"
              )
            end

            max_bytes = 50.megabytes
            file_size = File.size(import_file_path)
            if file_size > max_bytes
              return render_api_error(
                message: "Uploaded file is too large (max 50 MB)",
                status: :unprocessable_entity,
                code: "file_too_large"
              )
            end

            # For PDF uploads, the data stored/processed is the converted CSV, so reflect
            # that in the GecImport filename (consistent with GecImportUpload.filename).
            import_display_filename = if pdf_file?(file)
              "#{File.basename(file.original_filename.to_s, ".*")}.csv"
            else
              File.basename(file.original_filename || import_file_path)
            end

            upload_request_id = params[:upload_request_id].to_s.strip.presence
            existing_import = find_existing_background_import(
              upload_request_id: upload_request_id,
              gec_list_date: gec_list_date,
              filename: import_display_filename,
              import_type: import_type
            )
            if existing_import
              unless retryable_pending_import?(existing_import)
                return render json: {
                  message: existing_import.status == "completed" ? "GEC import already completed" : "GEC import already queued in background",
                  async: true,
                  duplicate_request: true,
                  import: existing_import.as_json(only: [ :id, :gec_list_date, :filename, :total_records, :new_records, :updated_records, :removed_records, :transferred_records, :re_vetted_count, :ambiguous_dob_count, :import_type, :status, :metadata ])
                }, status: :accepted
              end
            end

            gec_import = existing_import || GecImport.create!(
              gec_list_date: gec_list_date,
              filename: import_display_filename,
              uploaded_by_user: current_user,
              import_type: import_type,
              status: "pending",
              metadata: {
                "stage" => "queued",
                "progress_percent" => 0,
                "pdf_qa" => pdf_qa,
                "pdf_warnings" => pdf_warnings,
                "mode" => "background",
                "upload_request_id" => upload_request_id
              }
            )
            gec_import.update!(
              status: "pending",
              metadata: (gec_import.metadata || {}).merge({
                "stage" => "queued",
                "progress_percent" => 0,
                "pdf_qa" => pdf_qa,
                "pdf_warnings" => pdf_warnings,
                "mode" => "background",
                "upload_request_id" => upload_request_id,
                "error" => nil,
                "active_job_id" => nil,
                "enqueued_at" => nil
              })
            )

            begin
              preserve_raw_upload!(gec_import: gec_import, file: file)

              stored_filename = File.basename(file.original_filename || import_file_path)
              stored_content_type = file.content_type

              upload_payload = gec_import.upload_payload
              upload_payload&.destroy
              upload_payload = GecImportUpload.create!(
                gec_import: gec_import,
                filename: stored_filename,
                content_type: stored_content_type,
                file_data: File.binread(import_file_path)
              )

              job = GecImportJob.perform_later(
                gec_import_id: gec_import.id,
                upload_id: upload_payload.id,
                gec_list_date: gec_list_date.to_s,
                uploaded_by_user_id: current_user&.id,
                sheet_name: sheet_name,
                import_type: import_type,
                confirm_review: confirm_review
              )

              gec_import.update_columns(
                metadata: (gec_import.metadata || {}).merge({
                  "mode" => "background",
                  "queue_backend" => Rails.application.config.active_job.queue_adapter.to_s,
                  "active_job_id" => job.job_id,
                  "enqueued_at" => Time.current.iso8601
                })
              )
            rescue StandardError => e
              upload_payload&.destroy
              S3Service.delete(gec_import.raw_file_s3_key) if gec_import.raw_file_s3_key.present?
              gec_import.update_columns(raw_file_s3_key: nil, raw_filename: nil, raw_content_type: nil)
              gec_import.update!(
                status: "failed",
                metadata: (gec_import.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => "Failed to queue import: #{e.message}" })
              )

              return render_api_error(
                message: "Failed to queue import: #{e.message}",
                status: :unprocessable_entity,
                code: "import_enqueue_failed"
              )
            end

            render json: {
              message: "GEC import queued in background",
              async: true,
              import: gec_import.as_json(only: [ :id, :gec_list_date, :filename, :total_records, :new_records, :updated_records, :removed_records, :transferred_records, :re_vetted_count, :ambiguous_dob_count, :import_type, :status, :metadata ])
            }, status: :accepted
          else
            service = GecImportService.new(
              file_path: import_file_path,
              gec_list_date: gec_list_date,
              uploaded_by_user: current_user,
              sheet_name: sheet_name,
              import_type: import_type
            )

            result = service.call

            if result.success
              if pdf_qa.present? || pdf_warnings.any?
                result.gec_import.update!(
                  metadata: (result.gec_import.metadata || {}).merge({
                    "pdf_qa" => pdf_qa,
                    "pdf_warnings" => pdf_warnings
                  }.compact)
                )
              end
              preserve_raw_upload!(gec_import: result.gec_import, file: file)
              preserve_import_artifact!(
                gec_import: result.gec_import,
                file_path: artifact_file_path_for_upload(import_file_path: import_file_path, csv_tempfile: csv_tempfile),
                filename: artifact_filename_for_upload(file, import_file_path),
                content_type: artifact_content_type_for_upload(file)
              )
              log_audit!(result.gec_import, action: "gec_import", changed_data: result.stats)

              render json: {
                message: "GEC voter list imported successfully",
                import: result.gec_import.as_json(only: [ :id, :gec_list_date, :filename, :total_records, :new_records, :updated_records, :removed_records, :transferred_records, :re_vetted_count, :ambiguous_dob_count, :import_type, :status, :metadata ]),
                stats: result.stats,
                change_summary: result.gec_import.change_summary,
                pdf_qa: pdf_qa,
                errors: result.errors.first(20)
              }, status: :created
            else
              render_api_error(
                message: "Import failed: #{result.errors.first}",
                status: :unprocessable_entity,
                code: "import_failed",
                details: result.errors.first(20)
              )
            end
          end
        ensure
          csv_tempfile&.close!
        end
      end

      # POST /api/v1/gec_voters/preview
      # Preview a GEC voter list file without importing
      def preview
        file = params[:file]
        unless file.respond_to?(:tempfile)
          return render_api_error(
            message: "No file uploaded",
            status: :unprocessable_entity,
            code: "missing_file"
          )
        end

        if pdf_file?(file)
          if File.zero?(file.tempfile.path)
            return render_api_error(
              message: "Uploaded PDF preview is empty",
              status: :unprocessable_entity,
              code: "empty_file"
            )
          end

          if File.size(file.tempfile.path) > 50.megabytes
            return render_api_error(
              message: "Uploaded PDF preview is too large (max 50 MB)",
              status: :unprocessable_entity,
              code: "file_too_large"
            )
          end

          preview_request_id = params[:preview_request_id].to_s.strip.presence || SecureRandom.uuid
          preview = GecPdfPreview.find_by(preview_request_id: preview_request_id, uploaded_by_user: current_user)
          created_preview = false

          unless preview
            storage_attrs = nil
            begin
              storage_attrs = pdf_preview_storage_attributes(file, preview_request_id)
              unless storage_attrs
                return render_api_error(
                  message: "Failed to store PDF preview upload. Please try again.",
                  status: :service_unavailable,
                  code: "preview_storage_error"
                )
              end
              preview = GecPdfPreview.create!(
                preview_request_id: preview_request_id,
                uploaded_by_user: current_user,
                filename: File.basename(file.original_filename || "upload.pdf"),
                content_type: file.content_type,
                status: "pending",
                **storage_attrs
              )
              created_preview = true
            rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
              preview = GecPdfPreview.find_by(
                preview_request_id: preview_request_id,
                uploaded_by_user: current_user
              )
              raise e unless preview
            rescue StandardError
              if storage_attrs.is_a?(Hash) && storage_attrs[:file_s3_key].present?
                S3Service.delete(storage_attrs[:file_s3_key])
              end
              raise
            end
          end

          if created_preview
            begin
              GecPdfPreviewJob.perform_later(gec_pdf_preview_id: preview.id)
            rescue StandardError => e
              source_deleted = cleanup_pdf_preview_source!(preview)
              update_attrs = {
                status: "failed",
                error_message: "Failed to queue PDF preview: #{e.message}",
                result_data: {},
                file_data: nil
              }
              update_attrs[:file_s3_key] = nil if source_deleted
              preview.update!(update_attrs)
            end
          end

          return render json: pdf_preview_json(preview), status: pdf_preview_response_status(preview)
        end

        service = GecImportService.new(
          file_path: file.tempfile.path,
          gec_list_date: Date.today, # doesn't matter for preview
          sheet_name: requested_sheet_name(file)
        )

        begin
          preview_data = service.preview(limit: (params[:limit] || 20).to_i)
        rescue => e
          return render_api_error(
            message: "Failed to parse file: #{e.message}",
            status: :unprocessable_entity,
            code: "parse_error"
          )
        end

        render json: {
          source_type: "spreadsheet",
          sheets: preview_data[:sheets],
          headers: preview_data[:headers],
          column_map: preview_data[:column_map],
          row_count: preview_data[:row_count],
          preview_rows: preview_data[:preview_rows]
        }
      end

      def preview_status
        preview_request_id = params[:preview_request_id].to_s.strip
        if preview_request_id.blank?
          return render_api_error(
            message: "preview_request_id is required",
            status: :unprocessable_entity,
            code: "missing_preview_request_id"
          )
        end

        preview = GecPdfPreview.find_by(preview_request_id: preview_request_id, uploaded_by_user: current_user)
        unless preview
          return render_api_error(
            message: "PDF preview not found",
            status: :not_found,
            code: "preview_not_found"
          )
        end

        render json: pdf_preview_json(preview), status: pdf_preview_response_status(preview)
      end

      # GET /api/v1/gec_voters/imports
      # List past GEC imports
      def imports
        imports = GecImport.includes(:uploaded_by_user).latest.limit(20)
        skipped_counts = GecImportSkippedRow.where(gec_import_id: imports.map(&:id)).group(:gec_import_id, :resolution_status).count
        rows = imports.map do |imp|
          json = import_json(imp, skipped_counts_by_import: skipped_counts)
          if %w[pending processing].include?(imp.status)
            cached = begin
              Rails.cache.read("gec_import_progress:#{imp.id}")
            rescue StandardError
              nil
            end
            json["metadata"] = (json["metadata"] || {}).merge(cached || {})
          end
          json
        end

        render json: { imports: rows }
      end

      # POST /api/v1/gec_voters/imports/:id/activate_election_day
      def activate_election_day_import
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        unless gec_import.status == "completed"
          return render_api_error(
            message: "Only completed GEC imports can be activated for election day",
            status: :unprocessable_entity,
            code: "import_not_completed"
          )
        end

        gec_import.activate_for_election!(actor_user: current_user)
        log_audit!(
          gec_import,
          action: "gec_election_day_import_activated",
          changed_data: {
            active_election_day: [ false, true ],
            gec_list_date: [ nil, gec_import.gec_list_date ]
          }
        )

        render json: {
          message: "Election-day GEC list activated",
          import: import_json(gec_import.reload)
        }
      end

      # GET /api/v1/gec_voters/imports/:id/view_data
      # Preview the parsed import artifact for an existing import.
      def view_import_data
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        unless gec_import.import_artifact_available?
          return render_api_error(message: "Parsed import data is not available for this import", status: :not_found, code: "parsed_data_not_available")
        end

        preview = build_existing_import_preview(
          gec_import,
          page: (params[:page] || 1).to_i,
          per_page: (params[:per_page] || 100).to_i,
          q: params[:q].to_s,
          village: params[:village].to_s
        )
        unless preview
          return render_api_error(message: "Could not load parsed import data", status: :service_unavailable, code: "artifact_unavailable")
        end

        render json: {
          import: import_json(gec_import),
          preview: preview
        }
      end

      # GET /api/v1/gec_voters/imports/:id/changes
      # View persisted change rows for an existing import.
      def view_import_changes
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        per_page = [ (params[:per_page] || 100).to_i, 200 ].min
        page = [ (params[:page] || 1).to_i, 1 ].max
        type = params[:type].to_s.presence || "all"
        q = params[:q].to_s.strip

        raw_counts = gec_import.change_records.group(:change_type).count
        routed_rows = import_routed_to_unassigned_rows(gec_import)
        routed_rows = apply_routed_to_unassigned_search_filter(routed_rows, q) if q.present? && type == "routed_to_unassigned"

        if type == "routed_to_unassigned"
          total_rows = routed_rows.length
          total_pages = total_rows.zero? ? 1 : (total_rows.to_f / per_page).ceil
          page = [ page, total_pages ].min
          offset = (page - 1) * per_page
          rows = routed_rows.slice(offset, per_page) || []
        else
          scope = gec_import.change_records.latest_first
          scope = apply_change_type_filter(scope, type)
          scope = apply_change_search_filter(scope, q) if q.present?

          total_rows = scope.count
          total_pages = total_rows.zero? ? 1 : (total_rows.to_f / per_page).ceil
          page = [ page, total_pages ].min
          rows = scope.offset((page - 1) * per_page).limit(per_page)
        end

        render json: {
          import: import_json(gec_import),
          changes: type == "routed_to_unassigned" ? rows : rows.map { |row| import_change_json(row) },
          counts: {
            all: raw_counts.values.sum,
            new: raw_counts["new"].to_i,
            changed: raw_counts["updated"].to_i + raw_counts["transferred"].to_i,
            updated: raw_counts["updated"].to_i,
            removed: raw_counts["removed"].to_i,
            transferred: raw_counts["transferred"].to_i,
            routed_to_unassigned: gec_import.metadata["unassigned"].to_i
          },
          filters: {
            type: type,
            q: q
          },
          pagination: {
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            total_rows: total_rows
          }
        }
      end

      # GET /api/v1/gec_voters/imports/:id/skipped_rows
      def view_import_skipped_rows
        gec_import = GecImport.includes(:uploaded_by_user).find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        per_page = [ (params[:per_page] || 25).to_i, 100 ].min
        page = [ (params[:page] || 1).to_i, 1 ].max
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
          filters: {
            status: status,
            q: q
          },
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

      # GET /api/v1/gec_voters/imports/:id/view_original
      # Open the true raw uploaded file when available.
      def view_original
        gec_import = GecImport.find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        unless gec_import.raw_source_available?
          return render_api_error(message: "Original uploaded file is not available for this import", status: :not_found, code: "file_not_available")
        end

        content_type = gec_import.raw_content_type.presence || "application/octet-stream"
        filename = gec_import.raw_source_filename || gec_import.filename || "gec_import_#{gec_import.id}"
        view_url = S3Service.presigned_url(
          gec_import.raw_file_s3_key,
          expires_in: 1800,
          filename: filename,
          disposition: :inline
        )
        unless view_url
          return render_api_error(message: "Could not generate original file link", status: :service_unavailable, code: "s3_error")
        end

        render json: {
          view_url: view_url,
          filename: filename,
          content_type: content_type,
          inline_supported: content_type.include?("pdf")
        }
      end

      # GET /api/v1/gec_voters/imports/:id/download
      # Download the best available file for this import, preferring the raw source file.
      def download_import
        gec_import = GecImport.find_by(id: params[:id])
        unless gec_import
          return render_api_error(message: "Import not found", status: :not_found, code: "not_found")
        end

        unless gec_import.downloadable_file_available?
          return render_api_error(message: "Download file is not available for this import", status: :not_found, code: "file_not_available")
        end

        download_url = S3Service.presigned_url(
          gec_import.downloadable_file_key,
          expires_in: 300,
          filename: gec_import.downloadable_filename,
          disposition: :attachment
        )
        unless download_url
          return render_api_error(message: "Could not generate download link", status: :service_unavailable, code: "s3_error")
        end

        render json: {
          download_url: download_url,
          filename: gec_import.downloadable_filename || "gec_import_#{gec_import.id}"
        }
      end

      # POST /api/v1/gec_voters/match
      # Test matching for a specific supporter against GEC list
      def match
        matches = GecVoter.find_matches(
          first_name: params[:first_name],
          last_name: params[:last_name],
          dob: params[:dob].present? ? (Date.parse(params[:dob]) rescue nil) : nil,
          village_name: params[:village_name]
        )

        render json: {
          matches: matches.map do |m|
            {
              gec_voter: m[:gec_voter].as_json(only: [ :id, :first_name, :middle_name, :last_name, :dob, :birth_year, :address, :village_name, :precinct_id, :precinct_number, :voter_registration_number ]),
              confidence: m[:confidence],
              match_type: m[:match_type]
            }
          end
        }
      end

      # POST /api/v1/gec_voters/bulk_vet
      # Re-vet all existing supporters against the current GEC list.
      # Useful after importing a new GEC list.
      def bulk_vet
        scope = Supporter.working_supporters

        # Optional: only vet unverified supporters
        scope = scope.unverified if params[:unverified_only] == "true"

        # Optional: filter by village
        if params[:village_id].present?
          scope = scope.where(village_id: params[:village_id])
        end

        total = scope.count
        results = { auto_verified: 0, flagged: 0, referral: 0, unregistered: 0, skipped: 0, errors: 0 }
        gec_data_loaded = GecVoter.active.exists?

        if gec_data_loaded
          scope.find_each do |supporter|
            result = GecVettingService.new(supporter, gec_data_loaded: true).call
            results[result.status] += 1
          rescue StandardError => e
            results[:errors] += 1
            Rails.logger.warn("Bulk vet error for supporter #{supporter.id}: #{e.message}")
          end
        else
          results[:skipped] = total
        end

        log_audit!(nil, action: "bulk_gec_vet", changed_data: results.merge(total: total))

        render json: {
          message: "Bulk vetting complete",
          total: total,
          results: results
        }
      end

      private

      def apply_loose_search(scope, query)
        tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?).first(6)
        return scope if tokens.empty?

        tokens.reduce(scope) do |relation, token|
          sanitized = ActiveRecord::Base.sanitize_sql_like(token)
          pattern = "%#{sanitized}%"

          relation.where(
            "LOWER(first_name) LIKE :pattern OR LOWER(middle_name) LIKE :pattern OR LOWER(last_name) LIKE :pattern OR LOWER(village_name) LIKE :pattern OR LOWER(voter_registration_number) LIKE :pattern OR LOWER(COALESCE(precinct_number, '')) LIKE :pattern",
            pattern: pattern
          )
        end
      end

      def pdf_file?(file)
        filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : ""
        content_type = file.respond_to?(:content_type) ? file.content_type.to_s : ""

        filename.downcase.end_with?(".pdf") || content_type.include?("pdf")
      end

      def requested_sheet_name(file)
        return nil if pdf_file?(file)

        params[:sheet_name].to_s.strip.presence
      end

      def build_pdf_parse_cache_key(file_path)
        digest = Digest::SHA256.file(file_path).hexdigest
        "gec_pdf_parse:v1:#{digest}"
      rescue StandardError => e
        Rails.logger.warn("PDF parse cache key generation failed: #{e.class}: #{e.message}")
        nil
      end

      # Cache only the lightweight QA summary (not the full rows array which can be 30-60 MB
      # for a full ~60k-voter GEC list). On a cache hit we skip re-parsing for QA purposes
      # but still need to write_normalized_csv from a fresh parse — so the cache avoids the
      # QA overhead only; the caller still parses rows when needed.
      def write_cached_pdf_parse(cache_key, parsed)
        return if cache_key.blank?

        Rails.cache.write(
          cache_key,
          { qa: parsed.qa, warnings: parsed.warnings, errors: parsed.errors },
          expires_in: 20.minutes
        )
      end

      # Returns a lightweight cached result (qa/warnings/errors only, rows=[]).
      # Callers must re-parse if they need full row data.
      def read_cached_pdf_parse(cache_key)
        return nil if cache_key.blank?

        cached = begin
          Rails.cache.read(cache_key)
        rescue StandardError
          nil
        end
        return nil unless cached.is_a?(Hash) && cached.key?(:qa)

        GecPdfParserService::Result.new(
          rows: [],
          qa: cached[:qa] || {},
          warnings: cached[:warnings] || [],
          errors: cached[:errors] || []
        )
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
            parse_cache_key: nil,
            preview_rows: Array(result_data["preview_rows"])
          )
        elsif preview.failed?
          json[:error] = preview.error_message.presence || "PDF preview failed"
        end

        json
      end

      def pdf_preview_response_status(preview)
        return :ok if preview.completed? || preview.failed?

        :accepted
      end

      def pdf_preview_storage_attributes(file, preview_request_id)
        return { file_data: File.binread(file.tempfile.path) } unless S3Service.enabled?

        filename = File.basename(file.original_filename.to_s.presence || "upload.pdf")
        safe_filename = S3Service.safe_filename(filename, fallback: "preview.pdf")
        s3_key = "gec-pdf-previews/#{preview_request_id}/source/#{safe_filename}"
        content_type = file.content_type.to_s.presence || "application/pdf"
        upload_result = File.open(file.tempfile.path, "rb") do |io|
          S3Service.upload(s3_key, io, content_type: content_type)
        end
        return nil unless upload_result

        { file_s3_key: s3_key }
      end

      def cleanup_pdf_preview_source!(preview)
        return true unless preview&.file_s3_key.present?

        S3Service.delete(preview.file_s3_key)
      rescue StandardError => e
        Rails.logger.warn(
          "GecVotersController preview #{preview.id}: failed to delete S3 preview source " \
          "#{preview.file_s3_key}: #{e.class}: #{e.message}"
        )
        false
      end

      def import_json(imp, skipped_counts_by_import: nil)
        json = imp.as_json(only: [ :id, :gec_list_date, :filename, :total_records, :new_records, :updated_records, :removed_records, :transferred_records, :re_vetted_count, :ambiguous_dob_count, :import_type, :status, :created_at, :metadata, :active_election_day, :activated_for_election_at ])
        json["uploaded_by_email"] = imp.uploaded_by_user&.email
        json["activated_for_election_by_email"] = imp.activated_for_election_by_user&.email
        json["has_import_artifact"] = imp.import_artifact_available?
        json["has_original_file"] = imp.raw_source_available?
        json["has_downloadable_file"] = imp.downloadable_file_available?
        json["raw_filename"] = imp.raw_filename
        json["original_filename"] = imp.original_filename
        json["raw_content_type"] = imp.raw_content_type
        json["original_content_type"] = imp.original_content_type
        counts_for_import = if skipped_counts_by_import
          skipped_counts_by_import.each_with_object(Hash.new(0)) do |((import_id, status), count), memo|
            memo[status] = count if import_id == imp.id
          end
        else
          imp.skipped_rows.group(:resolution_status).count
        end
        json["skipped_rows_count"] = counts_for_import.values.sum
        json["pending_skipped_rows_count"] = counts_for_import["pending"].to_i
        json
      end

      def find_existing_background_import(upload_request_id:, gec_list_date:, filename:, import_type:)
        scope = GecImport.where(
          uploaded_by_user: current_user,
          gec_list_date: gec_list_date,
          filename: filename,
          import_type: import_type
        ).order(created_at: :desc)

        if upload_request_id.present?
          exact_match = scope
            .where(status: %w[pending processing completed])
            .where("metadata ->> 'upload_request_id' = ?", upload_request_id)
            .first
          return exact_match if exact_match
        end

        scope
          .where(status: %w[pending processing])
          .where("created_at >= ?", 10.minutes.ago)
          .first
      end

      def retryable_pending_import?(gec_import)
        gec_import.status == "pending" && gec_import.metadata.to_h["active_job_id"].blank?
      end

      def import_change_json(change)
        {
          id: change.id,
          change_type: change.change_type,
          row_number: change.row_number,
          first_name: change.first_name,
          middle_name: change.middle_name,
          last_name: change.last_name,
          voter_registration_number: change.voter_registration_number,
          village_name: change.village_name,
          previous_village_name: change.previous_village_name,
          birth_year: change.birth_year,
          dob: change.dob,
          details: change.details || {}
        }
      end

      def import_routed_to_unassigned_rows(gec_import)
        dataset = fetch_cached_import_viewer_dataset(gec_import)
        return [] unless dataset.is_a?(Hash)

        rows = Array(dataset["rows"])
        source_type = dataset["source_type"].to_s

        rows.each_with_index.filter_map do |row, index|
          next unless ActiveModel::Type::Boolean.new.cast(row["routed_to_unassigned"])

          {
            id: "routed-to-unassigned-#{index + 1}",
            change_type: "routed_to_unassigned",
            row_number: index + 2,
            first_name: row["first_name"],
            middle_name: row["middle_name"],
            last_name: row["last_name"],
            voter_registration_number: row["voter_registration_number"],
            village_name: GecImportService::UNASSIGNED_VILLAGE_NAME,
            previous_village_name: routed_to_unassigned_source_village(row, source_type),
            birth_year: row["birth_year"],
            dob: row["dob"],
            details: {
              source_name: routed_to_unassigned_source_name(row),
              source_village_name: routed_to_unassigned_source_village(row, source_type),
              reason: "The importer could not safely match this row to a canonical Guam village, so it was routed to Unassigned for review transparency.",
              changed_fields: {
                village_name: {
                  before: routed_to_unassigned_source_village(row, source_type).presence,
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

      def import_skipped_row_json(skipped_row)
        {
          id: skipped_row.id,
          row_number: skipped_row.row_number,
          message: skipped_row.message,
          source_name: skipped_row.source_name,
          first_name: skipped_row.first_name,
          middle_name: skipped_row.middle_name,
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
          resolved_gec_voter: skipped_row.resolved_gec_voter&.as_json(only: [ :id, :first_name, :middle_name, :last_name, :village_name, :voter_registration_number, :birth_year, :dob ])
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
          "LOWER(first_name) LIKE :q OR LOWER(COALESCE(middle_name, '')) LIKE :q OR LOWER(last_name) LIKE :q OR LOWER(village_name) LIKE :q OR LOWER(previous_village_name) LIKE :q OR LOWER(voter_registration_number) LIKE :q",
          q: like
        )
      end

      def apply_routed_to_unassigned_search_filter(rows, query)
        like = query.downcase
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
          ].any? { |value| value.to_s.downcase.include?(like) }
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
          "LOWER(COALESCE(first_name, '')) LIKE :q OR LOWER(COALESCE(middle_name, '')) LIKE :q OR LOWER(COALESCE(last_name, '')) LIKE :q OR LOWER(COALESCE(village_name, '')) LIKE :q OR LOWER(COALESCE(voter_registration_number, '')) LIKE :q OR LOWER(COALESCE(source_name, '')) LIKE :q",
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

      def preserve_raw_upload!(gec_import:, file:)
        return unless S3Service.enabled?

        raw_filename = File.basename(file.original_filename.to_s.presence || gec_import.filename.to_s)
        raw_content_type = file.respond_to?(:content_type) ? file.content_type.to_s.presence : nil
        raw_content_type ||= "application/octet-stream"
        safe_filename = S3Service.safe_filename(raw_filename, fallback: "raw_upload")
        s3_key = "gec-imports/#{gec_import.id}/raw/#{safe_filename}"
        upload_result = File.open(file.tempfile.path, "rb") do |io|
          S3Service.upload(s3_key, io, content_type: raw_content_type)
        end
        unless upload_result
          Rails.logger.error("GecVotersController import #{gec_import.id}: raw upload preservation failed; import will continue without raw source file")
          return
        end

        gec_import.update_columns(
          raw_file_s3_key: s3_key,
          raw_filename: raw_filename,
          raw_content_type: raw_content_type
        )
      rescue StandardError => e
        Rails.logger.error("GecVotersController import #{gec_import.id}: raw preservation error: #{e.class}: #{e.message}; import will continue without raw source file")
      end

      def preserve_import_artifact!(gec_import:, file_path:, filename:, content_type:)
        return unless S3Service.enabled?

        safe_filename = S3Service.safe_filename(filename, fallback: "import_artifact")
        s3_key = "gec-imports/#{gec_import.id}/artifact/#{safe_filename}"
        upload_result = File.open(file_path, "rb") do |io|
          S3Service.upload(s3_key, io, content_type: content_type)
        end
        unless upload_result
          Rails.logger.warn("GecVotersController import #{gec_import.id}: import artifact preservation failed")
          return
        end

        gec_import.update_columns(
          original_file_s3_key: s3_key,
          original_filename: filename,
          original_content_type: content_type
        )
      rescue StandardError => e
        Rails.logger.warn("GecVotersController import #{gec_import.id}: artifact preservation error: #{e.class}: #{e.message}")
      end

      def artifact_filename_for_upload(file, import_file_path)
        if pdf_file?(file)
          "#{File.basename(file.original_filename.to_s, ".*")}.csv"
        else
          File.basename(file.original_filename.presence || import_file_path)
        end
      end

      def artifact_file_path_for_upload(import_file_path:, csv_tempfile:)
        csv_tempfile&.path.presence || import_file_path
      end

      def artifact_content_type_for_upload(file)
        pdf_file?(file) ? "text/csv" : (file.content_type.presence || "application/octet-stream")
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
        offset = (effective_page - 1) * normalized_per_page
        page_rows = filtered_rows.slice(offset, normalized_per_page) || []

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
        cached = begin
          Rails.cache.read(cache_key)
        rescue StandardError
          nil
        end
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
        "gec_import_viewer:v4:#{gec_import.id}:#{Digest::SHA256.hexdigest(artifact_version)}"
      end

      def import_viewer_cache_row_limit
        100_000
      end

      def dataset_cacheable?(dataset)
        dataset["row_count"].to_i <= import_viewer_cache_row_limit
      end

      def build_import_viewer_dataset(gec_import)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

        dataset = if gec_import.imported_from_pdf?
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
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        if preview_data[:row_count].to_i >= 25_000 || elapsed_ms >= 1500
          Rails.logger.info(
            "GecVotersController import #{gec_import.id}: built viewer dataset " \
            "(rows=#{preview_data[:row_count]}, elapsed_ms=#{elapsed_ms})"
          )
        end
        dataset
      ensure
        temp&.close!
      end

      def apply_import_view_filters(rows:, source_type:, q:, village:)
        filtered = rows

        if village.present?
          village_field = source_type == "pdf" ? "village" : "village_name"
          filtered = filtered.select do |row|
            row[village_field].to_s.casecmp?(village.strip)
          end
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
    end
  end
end
