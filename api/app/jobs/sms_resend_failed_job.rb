# frozen_string_literal: true

class SmsResendFailedJob < ApplicationJob
  queue_as :default
  discard_on StandardError # SMS sends are not idempotent; retries can duplicate messages.

  def perform(delivery_ids:, recorded_by_user_id: nil)
    deliveries = OutreachDelivery.where(id: delivery_ids).includes(:sms_blast, :supporter).to_a
    return if deliveries.empty?

    messages = deliveries.map do |delivery|
      { to: delivery.recipient, body: delivery.sms_blast.message, supporter_id: delivery.supporter_id }
    end
    result = ClicksendClient.send_batch(messages)
    result_by_supporter_id = result[:results].to_a.index_by { |row| row[:supporter_id] }
    now = Time.current

    deliveries.each do |delivery|
      row = result_by_supporter_id[delivery.supporter_id]
      next unless row

      success = row[:success]
      delivery.update!(
        recipient: row[:to].presence || delivery.recipient,
        provider_message_id: row[:message_id],
        status: success ? "sent" : "failed",
        provider_status_text: row[:error],
        sent_at: success ? now : nil,
        failed_at: success ? nil : now,
        last_event_at: now
      )
      create_contact_attempt(delivery, recorded_by_user_id, success, row, now)
    rescue StandardError => e
      Rails.logger.error("[SmsResendFailedJob] resend tracking failed for delivery=#{delivery.id}: #{e.class} #{e.message}")
    end
  end

  private

  def create_contact_attempt(delivery, recorded_by_user_id, success, row, now)
    return if recorded_by_user_id.blank?

    SupporterContactAttempt.create!(
      supporter: delivery.supporter,
      recorded_by_user_id: recorded_by_user_id,
      channel: "sms",
      outcome: success ? "attempted" : "unavailable",
      note: "SMS resend #{success ? 'queued/sent' : 'failed'}: #{delivery.sms_blast.message.to_s.truncate(120)}#{row[:message_id].present? ? " Provider ID: #{row[:message_id]}." : ''}#{row[:error].present? ? " Error: #{row[:error]}." : ''}",
      recorded_at: now
    )
  end
end
