# frozen_string_literal: true

require "base64"
require "openssl"

module Api
  module V1
    class EmailController < ApplicationController
      include Authenticatable
      include OutreachGovernance
      before_action :authenticate_request
      skip_before_action :authenticate_request, only: [ :resend_webhook ]
      before_action :require_coordinator_or_above!, only: [ :blast, :blasts, :blast_status, :blast_deliveries, :resend_failed ]

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

        blast = EmailBlast.create!(
          status: "pending",
          subject: subject,
          body: body,
          filters: filters,
          total_recipients: count,
          initiated_by: current_user
        )

        SendEmailBlastJob.perform_later(email_blast_id: blast.id)

        render json: {
          queued: true,
          blast_id: blast.id,
          total_targeted: count,
          message: "Email blast queued successfully"
        }, status: :accepted
      end

      def blasts
        render json: {
          blasts: EmailBlast.recent.includes(:initiated_by).map do |blast|
            {
              id: blast.id,
              status: blast.status,
              subject: blast.subject,
              total_recipients: blast.total_recipients,
              sent_count: blast.sent_count,
              failed_count: blast.failed_count,
              progress_pct: blast.progress_pct,
              started_at: blast.started_at,
              completed_at: blast.completed_at,
              initiated_by: blast.initiated_by&.name || blast.initiated_by&.email
            }
          end
        }
      end

      def blast_status
        blast = EmailBlast.find_by(id: params[:id])
        return render_api_error(message: "Email blast not found", status: :not_found, code: "email_blast_not_found") unless blast

        render json: {
          id: blast.id,
          status: blast.status,
          subject: blast.subject,
          total_recipients: blast.total_recipients,
          sent_count: blast.sent_count,
          failed_count: blast.failed_count,
          progress_pct: blast.progress_pct,
          delivery_counts: blast.outreach_deliveries.group(:status).count,
          started_at: blast.started_at,
          completed_at: blast.completed_at,
          error_log: blast.error_log&.first(10),
          finished: blast.finished?
        }
      end

      def blast_deliveries
        blast = EmailBlast.find_by(id: params[:id])
        return render_api_error(message: "Email blast not found", status: :not_found, code: "email_blast_not_found") unless blast

        deliveries = blast.outreach_deliveries.includes(:supporter).recent_first.limit(500)
        render json: {
          deliveries: deliveries.map { |delivery| delivery_json(delivery) },
          counts: blast.outreach_deliveries.group(:status).count
        }
      end

      def resend_failed
        blast = EmailBlast.find_by(id: params[:id])
        return render_api_error(message: "Email blast not found", status: :not_found, code: "email_blast_not_found") unless blast
        return live_outreach_disabled_response unless live_outreach_enabled?

        deliveries = blast.outreach_deliveries.resendable.not_already_resent.includes(:supporter).to_a
        return render json: { queued: 0, message: "No failed or undelivered email recipients to resend." } if deliveries.empty?

        now = Time.current
        resend_delivery_ids = OutreachDelivery.transaction do
          deliveries.map do |original|
            OutreachDelivery.create!(
              channel: "email",
              email_blast: blast,
              supporter: original.supporter,
              resend_of: original,
              recipient: original.recipient,
              provider: "resend",
              status: "queued",
              last_event_at: now,
              metadata: { resend: true }
            ).id
          end
        end
        EmailResendFailedJob.perform_later(delivery_ids: resend_delivery_ids, recorded_by_user_id: current_user.id)

        render json: {
          queued: resend_delivery_ids.size,
          delivery_counts: blast.outreach_deliveries.group(:status).count,
          message: "Queued #{resend_delivery_ids.size} failed email recipient#{'s' unless resend_delivery_ids.size == 1} for resend."
        }, status: :accepted
      end

      def resend_webhook
        raw_body = request.raw_post
        unless valid_resend_signature?(raw_body)
          return render_api_error(message: "Invalid webhook signature", status: :unauthorized, code: "invalid_webhook_signature")
        end

        event = JSON.parse(raw_body)
        email_id = event.dig("data", "email_id").to_s
        return render json: { ok: true } if email_id.blank?

        delivery = OutreachDelivery.find_by(provider: "resend", provider_message_id: email_id)
        if delivery
          delivery.mark_provider_event!(
            status: OutreachDeliveryStatus.normalize_resend_event(event["type"]),
            occurred_at: Time.zone.parse(event["created_at"].to_s) || Time.current,
            metadata: { resend_event: event }
          )
        end

        render json: { ok: true }
      rescue JSON::ParserError
        render_api_error(message: "Invalid webhook payload", status: :bad_request, code: "invalid_webhook_payload")
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

      def delivery_json(delivery)
        supporter = delivery.supporter
        {
          id: delivery.id,
          supporter_id: supporter.id,
          supporter_name: supporter.print_name,
          recipient: delivery.recipient,
          status: delivery.status,
          provider_message_id: delivery.provider_message_id,
          provider_status_text: delivery.provider_status_text,
          sent_at: delivery.sent_at,
          delivered_at: delivery.delivered_at,
          failed_at: delivery.failed_at,
          last_event_at: delivery.last_event_at,
          resend_of_id: delivery.resend_of_id
        }
      end

      def valid_resend_signature?(raw_body)
        secret = ENV["RESEND_WEBHOOK_SIGNING_SECRET"].to_s
        return true if secret.blank? && Rails.env.test?
        return false if secret.blank?

        svix_id = request.headers["svix-id"].to_s
        svix_timestamp = request.headers["svix-timestamp"].to_s
        svix_signature = request.headers["svix-signature"].to_s
        return false if svix_id.blank? || svix_timestamp.blank? || svix_signature.blank?

        timestamp = Integer(svix_timestamp)
        return false if (Time.current.to_i - timestamp).abs > 300

        signed_payload = "#{svix_id}.#{svix_timestamp}.#{raw_body}"
        key = Base64.decode64(secret.delete_prefix("whsec_"))
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, signed_payload))
        svix_signature.split(" ").any? do |signature|
          version, value = signature.split(",", 2)
          version == "v1" && ActiveSupport::SecurityUtils.secure_compare(value, expected)
        rescue ArgumentError
          false
        end
      rescue ArgumentError
        false
      end

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
