# frozen_string_literal: true

module Api
  module V1
    class SmsController < ApplicationController
      include Authenticatable
      include OutreachGovernance
      before_action :authenticate_request
      before_action :require_coordinator_or_above!, only: [ :send_single, :blast, :blasts, :blast_status, :blast_deliveries, :sync_blast_receipts, :resend_failed ]

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

        filters = outreach_filters
        supporters = OutreachRecipientQuery.sms_scope(base_scope: Supporter.all, filters: filters)

        if params[:dry_run] == "true"
          return render json: OutreachRecipientQuery.preview(supporters).merge(dry_run: true, message: message)
        end

        count = supporters.count
        return live_outreach_disabled_response unless live_outreach_enabled?
        return recipient_review_required_response(count) unless OutreachRecipientQuery.reviewed?(params, expected_count: count)

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
          delivery_counts: blast.outreach_deliveries.group(:status).count,
          finished: blast.finished?
        }
      end

      def blast_deliveries
        blast = SmsBlast.find_by(id: params[:id])
        return render_api_error(message: "Blast not found", status: :not_found, code: "blast_not_found") unless blast

        render json: delivery_payload(blast.outreach_deliveries.includes(:supporter).recent_first)
      end

      def sync_blast_receipts
        blast = SmsBlast.find_by(id: params[:id])
        return render_api_error(message: "Blast not found", status: :not_found, code: "blast_not_found") unless blast

        updated = 0
        blast.outreach_deliveries.where(provider: "clicksend").where.not(provider_message_id: [ nil, "" ]).find_each do |delivery|
          result = ClicksendClient.sms_receipt(delivery.provider_message_id)
          next unless result[:success] && result[:receipt].is_a?(Hash)

          attrs = OutreachDeliveryStatus.normalize_clicksend_receipt(result[:receipt])
          delivery.mark_provider_event!(**attrs, occurred_at: Time.current, metadata: { clicksend_receipt: result[:receipt] })
          updated += 1
        end

        render json: { updated: updated, delivery_counts: blast.outreach_deliveries.group(:status).count }
      end

      def resend_failed
        blast = SmsBlast.find_by(id: params[:id])
        return render_api_error(message: "Blast not found", status: :not_found, code: "blast_not_found") unless blast
        return live_outreach_disabled_response unless live_outreach_enabled?

        deliveries = blast.outreach_deliveries.resendable.not_already_resent.includes(:supporter).to_a
        return render json: { resent: 0, message: "No failed or undelivered SMS recipients to resend." } if deliveries.empty?

        phones_and_bodies = deliveries.map { |delivery| { to: delivery.recipient, body: blast.message, supporter_id: delivery.supporter_id } }
        result = ClicksendClient.send_batch(phones_and_bodies)
        result_by_supporter_id = result[:results].index_by { |row| row[:supporter_id] }
        now = Time.current

        deliveries.each do |original|
          row = result_by_supporter_id[original.supporter_id]
          next unless row

          OutreachDelivery.create!(
            channel: "sms",
            sms_blast: blast,
            supporter: original.supporter,
            resend_of: original,
            recipient: row[:to].presence || original.recipient,
            provider: "clicksend",
            provider_message_id: row[:message_id],
            status: row[:success] ? "sent" : "failed",
            provider_status_text: row[:error],
            sent_at: row[:success] ? now : nil,
            failed_at: row[:success] ? nil : now,
            last_event_at: now,
            metadata: { resend: true }
          )
          SupporterContactAttempt.create!(
            supporter: original.supporter,
            recorded_by_user_id: current_user.id,
            channel: "sms",
            outcome: row[:success] ? "attempted" : "unavailable",
            note: "SMS resend #{row[:success] ? 'queued/sent' : 'failed'}: #{blast.message.to_s.truncate(120)}#{row[:message_id].present? ? " Provider ID: #{row[:message_id]}." : ''}#{row[:error].present? ? " Error: #{row[:error]}." : ''}",
            recorded_at: now
          )
        end

        render json: { resent: result[:sent], failed: result[:failed], delivery_counts: blast.outreach_deliveries.group(:status).count }
      end

      private

      def delivery_payload(scope)
        deliveries = scope.limit(500).map do |delivery|
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
        { deliveries: deliveries, counts: scope.unscope(:order).group(:status).count }
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
