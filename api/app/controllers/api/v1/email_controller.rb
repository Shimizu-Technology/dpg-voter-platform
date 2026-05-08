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
        supporters = supporters.where(motorcade_available: true) if params[:motorcade_available] == "true"
        supporters = supporters.where(registered_voter: true) if params[:registered_voter] == "true"
        supporters = supporters.where(yard_sign: true) if params[:yard_sign] == "true"

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

        SendEmailBlastJob.perform_later(
          subject: subject,
          body: body,
          filters: {
            "village_id" => params[:village_id],
            "motorcade_available" => params[:motorcade_available],
            "registered_voter" => params[:registered_voter],
            "yard_sign" => params[:yard_sign]
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
          from_email: ENV["RESEND_FROM_EMAIL"].presence || "(not set)"
        }
      end
    end
  end
end
