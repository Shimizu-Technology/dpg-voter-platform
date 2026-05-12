# frozen_string_literal: true

module Api
  module V1
    class EmailController < ApplicationController
      include Authenticatable
      include OutreachGovernance
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

        filters = outreach_filters
        supporters = OutreachRecipientQuery.email_scope(base_scope: Supporter.all, filters: filters)

        if params[:dry_run] == "true"
          sample_supporter = Supporter.new(
            first_name: "Maria", last_name: "Cruz",
            village: Village.find_by(name: "Tamuning") || Village.first
          )
          return render json: {
            dry_run: true,
            subject: subject,
            preview_subject: SupporterEmailService.preview_subject(subject, sample_supporter),
            preview_html: SupporterEmailService.preview_html(body, sample_supporter)
          }.merge(OutreachRecipientQuery.preview(supporters))
        end

        count = supporters.count
        return live_outreach_disabled_response unless live_outreach_enabled?
        return recipient_review_required_response(count) unless OutreachRecipientQuery.reviewed?(params, expected_count: count)

        SendEmailBlastJob.perform_later(
          subject: subject,
          body: body,
          filters: filters,
          initiated_by_user_id: current_user.id
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
