# frozen_string_literal: true

module Api
  module V1
    class EmailController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_coordinator_or_above!, only: [ :blast ]

      # POST /api/v1/email/blast
      # Send email to filtered supporters who opted in
      def blast
        subject = params[:subject]
        body = params[:body]

        if subject.blank? || body.blank?
          return render_api_error(
            message: "Subject and body are required",
            status: :unprocessable_entity,
            code: "email_content_required"
          )
        end

        supporters = Supporter.active
                              .where.not(email: [ nil, "" ])
                              .where(opt_in_email: true)

        # Optional filters
        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?
        supporters = supporters.where(registered_voter: true) if params[:registered_voter] == "true"

        count = supporters.count

        if params[:dry_run] == "true"
          sample_supporter = Supporter.new(
            first_name: "Maria", last_name: "Cruz",
            village: Village.find_by(name: "Tamuning") || Village.first
          )
          return render json: {
            dry_run: true,
            recipient_count: count,
            subject: subject,
            preview_subject: SupporterEmailService.preview_subject(subject, sample_supporter),
            preview_html: SupporterEmailService.preview_html(body, sample_supporter)
          }
        end

        return live_outreach_disabled_response unless live_outreach_enabled?

        SendEmailBlastJob.perform_later(
          subject: subject,
          body: body,
          filters: {
            "village_id" => params[:village_id],
            "registered_voter" => params[:registered_voter]
          }
        )

        render json: {
          queued: true,
          total_targeted: count,
          message: "Email blast queued successfully"
        }, status: :accepted
      end

      # GET /api/v1/email/status
      # Check if email sending is configured
      def status
        render json: {
          configured: SupporterEmailService.configured?,
          live_enabled: live_outreach_enabled?,
          from_email: ENV["RESEND_FROM_EMAIL"].presence || "(not set)"
        }
      end

      private

      def live_outreach_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV["DPG_LIVE_OUTREACH_ENABLED"]) == true
      end

      def live_outreach_disabled_response
        render_api_error(
          message: "Live SMS/email sending is off for this DPG environment. Use dry run, or enable this only in an approved DPG environment with sender credentials configured.",
          status: :forbidden,
          code: "live_outreach_disabled"
        )
      end
    end
  end
end
