# frozen_string_literal: true

class EmailResendFailedJob < ApplicationJob
  queue_as :default
  discard_on StandardError # Resend API calls are not idempotent; retries can duplicate email sends.

  BATCH_SIZE = 100
  BATCH_DELAY = 1.0

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

  def process_batch(delivery_ids, recorded_by_user_id)
    OutreachDelivery.where(id: delivery_ids).includes(:email_blast, :supporter).find_each do |delivery|
      send_resend_delivery(delivery, recorded_by_user_id)
    end
  end

  def mark_queued_deliveries_failed(delivery_ids, error)
    now = Time.current
    OutreachDelivery.where(id: delivery_ids, status: "queued").update_all(
      status: "failed",
      provider_status_text: "Resend job interrupted before completion: #{error.message}",
      failed_at: now,
      last_event_at: now,
      updated_at: now
    )
  rescue StandardError => cleanup_error
    Rails.logger.error("[EmailResendFailedJob] failed to reset queued deliveries after #{error.class}: #{cleanup_error.class} #{cleanup_error.message}")
  end

  def send_resend_delivery(delivery, recorded_by_user_id)
    blast = delivery.email_blast
    supporter = delivery.supporter
    now = Time.current

    begin
      response = Resend::Emails.send({
        from: ENV["RESEND_FROM_EMAIL"].presence || ENV["MAILER_FROM_EMAIL"].presence,
        to: delivery.recipient,
        subject: SupporterEmailService.preview_subject(blast.subject, supporter),
        html: SupporterEmailService.preview_html(blast.body, supporter),
        tags: [ { name: "email_blast_id", value: blast.id.to_s } ]
      })
      delivery.update!(
        provider_message_id: provider_message_id(response),
        status: "sent",
        provider_status_text: nil,
        sent_at: now,
        failed_at: nil,
        last_event_at: now
      )
      create_contact_attempt(delivery, recorded_by_user_id, "sent", nil, now)
    rescue StandardError => e
      delivery.update!(
        status: "failed",
        provider_status_text: e.message,
        failed_at: now,
        last_event_at: now
      )
      create_contact_attempt(delivery, recorded_by_user_id, "failed", e.message, now)
    end
  end

  def provider_message_id(response)
    if response.respond_to?(:id)
      response.id
    elsif response.is_a?(Hash)
      response[:id] || response["id"] || response.dig(:data, :id) || response.dig("data", "id")
    end
  end

  def create_contact_attempt(delivery, recorded_by_user_id, status, provider_status_text, now)
    return if recorded_by_user_id.blank?

    SupporterContactAttempt.create!(
      supporter: delivery.supporter,
      recorded_by_user_id: recorded_by_user_id,
      channel: "email",
      outcome: status == "sent" ? "attempted" : "unavailable",
      note: "Email resend #{status == 'sent' ? 'sent' : 'failed'}: #{delivery.email_blast.subject.to_s.truncate(120)}#{provider_status_text.present? ? " Error: #{provider_status_text}." : ''}",
      recorded_at: now
    )
  end
end
