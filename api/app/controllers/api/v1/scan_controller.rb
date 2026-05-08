# frozen_string_literal: true

module Api
  module V1
    class ScanController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_staff_entry_access!

      # POST /api/v1/scan
      # Accepts a base64 image and returns extracted form data
      def create
        image_data = params[:image]
        return render_missing_image_error if image_data.blank?

        result = FormScanner.extract(image_data)

        if result[:success]
          render json: {
            success: true,
            extracted: result[:data],
            confidence: result[:confidence] || {},
            message: "Form data extracted successfully"
          }
        else
          render json: {
            success: false,
            error: result[:error],
            code: "scan_extraction_failed",
            raw_response: result[:raw_response]
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/scan/batch
      # Accepts a base64 image and returns multiple extracted rows for review.
      def batch
        image_data = params[:image]
        return render_missing_image_error if image_data.blank?

        default_village_id = params[:default_village_id].presence
        if default_village_id.present? && !Village.exists?(id: default_village_id)
          return render_api_error(
            message: "Default village is invalid",
            status: :unprocessable_entity,
            code: "invalid_default_village"
          )
        end

        if default_village_id.present? && scoped_village_ids && !scoped_village_ids.include?(default_village_id.to_i)
          return render_api_error(
            message: "Village not in your assigned scope",
            status: :forbidden,
            code: "village_scope_denied"
          )
        end

        result = FormScanner.extract_batch(image_data, default_village_id: default_village_id)

        if result[:success]
          warning = if result[:partial_parse]
            "OCR response was partially truncated. Parsed complete rows only; verify all rows before saving."
          end

          render json: {
            success: true,
            rows: result[:rows] || [],
            total_detected: (result[:rows] || []).size,
            warning: warning,
            message: "Batch form data extracted successfully"
          }
        else
          render json: {
            success: false,
            error: result[:error],
            code: "scan_batch_extraction_failed",
            raw_response: result[:raw_response]
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/scan/telemetry
      # Accepts post-save batch OCR quality metrics for tuning.
      def telemetry
        payload = telemetry_params.to_h

        # Guard against oversized payloads (telemetry only, no DB persistence)
        if payload.to_json.bytesize > 10_000
          return render_api_error(message: "Telemetry payload too large", status: :unprocessable_entity)
        end

        Rails.logger.info(
          {
            event: "scan_batch_quality_telemetry",
            user_id: current_user&.id,
            user_role: current_user&.role,
            request_id: request.request_id,
            payload: payload
          }.to_json
        )

        render json: { success: true }
      end

      private

      def render_missing_image_error
        render_api_error(
          message: "Image data is required",
          status: :unprocessable_entity,
          code: "image_data_required"
        )
      end

      def telemetry_params
        params.fetch(:telemetry, {}).permit(
          :total_detected,
          :included_before_save,
          :created,
          :failed,
          :skipped,
          :rows_with_any_issues,
          :rows_with_critical_issues,
          :rows_with_warning_only,
          :scan_warning_present,
          :save_duration_ms,
          :default_village_id,
          issue_counts: {}
        )
      end
    end
  end
end
