# frozen_string_literal: true

module Api
  module V1
    class SmsController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_coordinator_or_above!, only: [ :send_single, :blast, :blasts, :blast_status ]

      # GET /api/v1/sms/status
      # Check ClickSend account status + balance
      def status
        balance = SmsService.balance
        render json: {
          configured: ENV["CLICKSEND_USERNAME"].present? && ENV["CLICKSEND_API_KEY"].present?,
          live_enabled: live_outreach_enabled?,
          balance: balance,
          sender_id: ENV["DPG_CLICKSEND_SENDER_ID"].presence || "DPG"
        }
      end

      # POST /api/v1/sms/send
      # Send a single SMS (for testing)
      def send_single
        phone = params[:phone]
        message = params[:message]

        if phone.blank? || message.blank?
          return render_api_error(
            message: "Phone and message required",
            status: :unprocessable_entity,
            code: "sms_phone_and_message_required"
          )
        end

        return live_outreach_disabled_response unless live_outreach_enabled?

        result = ClicksendClient.send_sms(to: phone, body: message)
        render json: result
      end

      # POST /api/v1/sms/blast
      # Send SMS to filtered supporters
      def blast
        message = params[:message]
        if message.blank?
          return render_api_error(
            message: "Message is required",
            status: :unprocessable_entity,
            code: "sms_message_required"
          )
        end

        supporters = Supporter.active.where.not(contact_number: [ nil, "" ]).where("TRIM(contact_number) != ''").where(opt_in_text: true)

        # Optional filters
        supporters = supporters.where(village_id: params[:village_id]) if params[:village_id].present?
        supporters = supporters.where(registered_voter: true) if params[:registered_voter] == "true"

        count = supporters.count

        if params[:dry_run] == "true"
          return render json: { dry_run: true, recipient_count: count, message: message }
        end

        return live_outreach_disabled_response unless live_outreach_enabled?

        filters = {
          "village_id" => params[:village_id],
          "registered_voter" => params[:registered_voter]
        }

        blast = SmsBlast.create!(
          status: "pending",
          message: message,
          filters: filters,
          total_recipients: 0,
          sent_count: 0,
          failed_count: 0,
          initiated_by: current_user
        )

        SmsBlastJob.perform_later(sms_blast_id: blast.id)

        render json: {
          queued: true,
          blast_id: blast.id,
          total_targeted: count,
          message: "SMS blast queued successfully"
        }, status: :accepted
      end

      # GET /api/v1/sms/blasts
      # Recent blast history
      def blasts
        blasts = SmsBlast.recent.includes(:initiated_by).map do |b|
          {
            id: b.id,
            status: b.status,
            message: b.message.truncate(80),
            total_recipients: b.total_recipients,
            sent_count: b.sent_count,
            failed_count: b.failed_count,
            progress_pct: b.progress_pct,
            started_at: b.started_at,
            completed_at: b.completed_at,
            initiated_by: b.initiated_by&.name || b.initiated_by&.email
          }
        end

        render json: { blasts: blasts }
      end

      # GET /api/v1/sms/blasts/:id
      # Poll blast progress
      def blast_status
        blast = SmsBlast.find_by(id: params[:id])
        unless blast
          return render_api_error(message: "Blast not found", status: :not_found, code: "blast_not_found")
        end

        render json: {
          id: blast.id,
          status: blast.status,
          message: blast.message,
          total_recipients: blast.total_recipients,
          sent_count: blast.sent_count,
          failed_count: blast.failed_count,
          progress_pct: blast.progress_pct,
          started_at: blast.started_at,
          completed_at: blast.completed_at,
          error_log: blast.error_log&.first(10),
          finished: blast.finished?
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
