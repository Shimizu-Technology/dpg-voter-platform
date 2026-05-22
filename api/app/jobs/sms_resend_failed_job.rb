# frozen_string_literal: true

class SmsResendFailedJob < ApplicationJob
  queue_as :default
  discard_on StandardError # SMS sends are not idempotent; retries can duplicate messages.

  BATCH_SIZE = 500 # ClickSend supports up to 1000, use 500 for safety
  BATCH_DELAY = 1.0 # seconds between batches to respect rate limits

  def perform(delivery_ids:, recorded_by_user_id: nil)
    delivery_ids.each_slice(BATCH_SIZE).with_index do |batch_ids, batch_idx|
      sleep(BATCH_DELAY) if batch_idx > 0
      process_batch(batch_ids, recorded_by_user_id)
    end
  rescue StandardError => e
    mark_queued_deliveries_failed(delivery_ids, e)
    raise
  end

  private

  def mark_queued_deliveries_failed(delivery_ids, error)
    now = Time.current
    OutreachDelivery.where(id: delivery_ids, status: "queued").update_all(
      status: "failed",
      provider_status_text: "SMS resend job interrupted before completion: #{error.message}",
      failed_at: now,
      last_event_at: now,
      updated_at: now
    )
  rescue StandardError => cleanup_error
    Rails.logger.error("[SmsResendFailedJob] failed to reset queued deliveries after #{error.class}: #{cleanup_error.class} #{cleanup_error.message}")
  end

  def process_batch(delivery_ids, recorded_by_user_id)
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
      unless row
        mark_delivery_failed(delivery, "ClickSend resend returned no result for this recipient", now)
        next
      end

      update_delivery_from_result(delivery, row, recorded_by_user_id, now)
    end
  end

  def update_delivery_from_result(delivery, row, recorded_by_user_id, now)
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

  def mark_delivery_failed(delivery, message, now)
    delivery.update!(
      status: "failed",
      provider_status_text: message,
      failed_at: now,
      last_event_at: now
    )
  rescue StandardError => e
    Rails.logger.error("[SmsResendFailedJob] failed to mark missing ClickSend result for delivery=#{delivery.id}: #{e.class} #{e.message}")
  end

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
