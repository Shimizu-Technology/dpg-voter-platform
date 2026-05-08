# frozen_string_literal: true

module Api
  module V1
    class ImportsController < ApplicationController
      include Authenticatable
      include AuditLoggable
      before_action :authenticate_request
      before_action :require_supporter_import_access!

      # POST /api/v1/imports/preview
      # Upload a file, parse it, return sheet metadata + sample rows for review.
      def preview
        file = params[:file]
        unless file.respond_to?(:tempfile)
          return render_api_error(
            message: "No file uploaded",
            status: :unprocessable_entity,
            code: "missing_file"
          )
        end

        unless valid_file_type?(file)
          return render_api_error(
            message: "Unsupported file type. Please upload .xlsx or .csv",
            status: :unprocessable_entity,
            code: "invalid_file_type"
          )
        end

        if file.size > 10.megabytes
          return render_api_error(
            message: "File too large. Maximum size is 10 MB.",
            status: :unprocessable_entity,
            code: "file_too_large"
          )
        end

        result = SpreadsheetParser.parse_metadata(
          file.tempfile.path,
          original_filename: file.original_filename
        )

        if result.errors.any?
          return render_api_error(
            message: result.errors.join("; "),
            status: :unprocessable_entity,
            code: "parse_error"
          )
        end

        # Store the file temporarily for the confirm step
        import_key = SecureRandom.hex(16)
        safe_ext = File.extname(file.original_filename).downcase
        safe_ext = ".xlsx" unless %w[.xlsx .csv].include?(safe_ext) # already validated above
        tmp_path = Rails.root.join("tmp", "imports", "#{import_key}#{safe_ext}")
        FileUtils.mkdir_p(tmp_path.dirname)
        FileUtils.cp(file.tempfile.path, tmp_path)

        # Clean up any stale temp files older than 1 hour
        cleanup_stale_imports!(exclude_key: import_key)

        render json: {
          import_key: import_key,
          filename: file.original_filename,
          sheets: result.sheets.map do |sheet|
            {
              name: sheet.name,
              index: sheet.index,
              row_count: sheet.row_count,
              headers: sheet.headers,
              sample_rows: sheet.sample_rows
            }
          end
        }
      end

      # POST /api/v1/imports/parse
      # Parse all rows from a specific sheet with column mapping. Returns full preview.
      def parse
        import_key = params[:import_key]
        sheet_index = params[:sheet_index].to_i
        column_mapping = params[:column_mapping]

        unless import_key.present? && import_key.match?(/\A[a-f0-9]{32}\z/)
          return render_api_error(message: "Invalid import key", status: :bad_request, code: "invalid_key")
        end

        file_path = find_import_file(import_key)
        unless file_path
          return render_api_error(message: "Import session expired. Please re-upload.", status: :gone, code: "expired")
        end

        unless column_mapping.is_a?(ActionController::Parameters) || column_mapping.is_a?(Hash)
          return render_api_error(message: "column_mapping is required", status: :bad_request, code: "missing_mapping")
        end

        mapping = {
          header_row: column_mapping[:header_row].to_i,
          columns: (column_mapping[:columns] || {}).transform_values { |v| v.to_i }
        }

        result = SpreadsheetParser.parse_rows(
          file_path,
          sheet_index: sheet_index,
          column_mapping: mapping,
          original_filename: file_path
        )

        # Check for duplicates against existing supporters
        result[:rows].each do |row|
          next if row["_skip"]
          next if row["first_name"].blank?

          dupes = check_duplicates(row)
          if dupes.any?
            row["_duplicate_matches"] = dupes.map { |d| { id: d.id, name: d.display_name, phone: d.contact_number } }
            row["_issues"] << "Possible duplicate: #{dupes.map(&:display_name).join(', ')}"
          end
        end

        render json: {
          rows: result[:rows],
          issues: result[:issues],
          total: result[:total],
          valid_count: result[:rows].count { |r| !r["_skip"] && r["_issues"].empty? },
          issue_count: result[:rows].count { |r| r["_issues"].any? },
          skip_count: result[:rows].count { |r| r["_skip"] }
        }
      end

      # POST /api/v1/imports/confirm
      # Actually create supporter records from reviewed data.
      def confirm
        import_key = params[:import_key]
        village_id = params[:village_id]
        rows = params[:rows]

        unless import_key.present? && import_key.match?(/\A[a-f0-9]{32}\z/)
          return render_api_error(message: "Invalid import key", status: :bad_request, code: "invalid_key")
        end

        # Village can come from: 1) village_id param (all rows), or 2) per-row village name
        default_village = village_id.present? ? Village.find_by(id: village_id) : nil

        # Enforce village scope for non-admin users
        if default_village && scoped_village_ids && !scoped_village_ids.include?(default_village.id)
          return render_api_error(message: "Village not in your assigned scope", status: :forbidden, code: "village_scope_denied")
        end
        has_per_row_village = rows.any? { |r| r["village"].present? }

        unless default_village || has_per_row_village
          return render_api_error(message: "village_id is required (or rows must include village names)", status: :bad_request, code: "missing_village")
        end

        # Pre-load village name → record lookup for per-row matching (scoped if user has area restrictions)
        if has_per_row_village
          village_scope = scoped_village_ids ? Village.where(id: scoped_village_ids) : Village.all
          village_lookup = village_scope.index_by { |v| v.name.downcase.strip }
        end

        unless rows.is_a?(Array) && rows.any?
          return render_api_error(message: "No rows to import", status: :bad_request, code: "empty_rows")
        end

        if rows.size > 5000
          return render_api_error(message: "Too many rows (#{rows.size}). Maximum is 5,000.", status: :unprocessable_entity, code: "too_many_rows")
        end

        created = 0
        skipped = 0
        errors = []
        audit_records = []

        # Partial import: each row saved independently so valid rows aren't blocked by bad ones
        rows.each_with_index do |row, idx|
          next if row["_skip"]

          # Resolve village: per-row name takes priority over default
          row_village = default_village
          if row["village"].present? && village_lookup
            matched = village_lookup[row["village"].downcase.strip]
            if matched
              row_village = matched
            else
              skipped += 1
              errors << { row: row["_row"] || (idx + 1), errors: [ "Unknown village: \"#{row['village']}\"" ] }
              next
            end
          end

          unless row_village
            skipped += 1
            errors << { row: row["_row"] || (idx + 1), errors: [ "No village assigned" ] }
            next
          end

          supporter = Supporter.new(
            first_name: row["first_name"],
            middle_name: row["middle_name"],
            last_name: row["last_name"],
            contact_number: row["contact_number"],
            dob: parse_date(row["dob"]),
            email: row["email"],
            street_address: row["street_address"],
            self_reported_registered_voter: row["registered_voter"],
            village: row_village,
            source: "bulk_import",
            attribution_method: "bulk_import",
            intake_status: "accepted",
            review_status: "pending",
            public_review_status: "not_applicable",
            status: "active",
            turnout_status: "unknown",
            verification_status: "unverified",
            entered_by: current_user
          )

          if supporter.save
            created += 1
            audit_records << {
              auditable_type: "Supporter",
              auditable_id: supporter.id,
              actor_user_id: current_user.id,
              action: "created",
              changed_data: normalize_changed_data(supporter.saved_changes.except("updated_at")),
              metadata: {
                "entry_mode" => "bulk_import",
                "import_key" => import_key,
                "import_row" => row["_row"] || (idx + 1),
                "ip_address" => request.remote_ip
              }.compact,
              created_at: Time.current
            }
          else
            skipped += 1
            errors << { row: row["_row"] || (idx + 1), errors: supporter.errors.full_messages }
          end
        end

        # Bulk insert audit logs (much faster than per-row INSERTs)
        AuditLog.insert_all(audit_records) if audit_records.any?

        # Clean up temp file
        cleanup_import_file(import_key) if import_key.present?

        log_audit!(nil, action: "bulk_import", changed_data: {
          "village" => default_village&.name || "per-row",
          "created" => created,
          "skipped" => skipped,
          "total_rows" => rows.size
        })

        render json: {
          message: "Import complete",
          created: created,
          skipped: skipped,
          errors: errors,
          village: default_village&.name || "multiple villages"
        }
      end

      private

      def valid_file_type?(file)
        ext = File.extname(file.original_filename).downcase
        %w[.xlsx .csv].include?(ext)
      end

      def find_import_file(key)
        dir = Rails.root.join("tmp", "imports")
        return nil unless Dir.exist?(dir)

        Dir.glob(dir.join("#{key}.*")).first
      end

      def cleanup_import_file(key)
        file = find_import_file(key)
        File.delete(file) if file && File.exist?(file)
      end

      def cleanup_stale_imports!(exclude_key: nil)
        dir = Rails.root.join("tmp", "imports")
        return unless Dir.exist?(dir)

        Dir.glob(dir.join("*")).each do |f|
          next if exclude_key && File.basename(f).start_with?(exclude_key)
          File.delete(f) if File.mtime(f) < 1.hour.ago
        end
      rescue StandardError => e
        Rails.logger.warn("Import cleanup failed: #{e.message}")
      end

      def check_duplicates(row)
        scope = Supporter.active

        matches = []

        # Phone match
        if row["contact_number"].present?
          phone_matches = scope.where(contact_number: row["contact_number"])
          matches.concat(phone_matches.to_a)
        end

        # Name + village match (can't check village yet since it's assigned at confirm time)
        if row["first_name"].present? && row["last_name"].present?
          name_matches = scope.where(
            "LOWER(first_name) = ? AND LOWER(last_name) = ?",
            row["first_name"].downcase.strip,
            row["last_name"].downcase.strip
          )
          matches.concat(name_matches.to_a)
        end

        matches.uniq(&:id).first(3) # Limit to 3 matches
      end

      def parse_date(str)
        return nil if str.blank?
        Date.parse(str)
      rescue Date::Error, ArgumentError
        nil
      end

      def audit_entry_mode
        "bulk_import"
      end
    end
  end
end
