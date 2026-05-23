# frozen_string_literal: true

class SmsSyncReceiptsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100
  BATCH_DELAY = 1.0
  TERMINAL_STATUSES = %w[delivered undelivered failed bounced suppressed complained].freeze

  def perform(sms_blast_id:)
    blast = SmsBlast.find_by(id: sms_blast_id)
    return unless blast

    updated = 0
    syncable_deliveries(blast).find_in_batches(batch_size: BATCH_SIZE).with_index do |batch, batch_idx|
      sleep(BATCH_DELAY) if batch_idx > 0
      updated += sync_batch(batch)
    end

    Rails.logger.info("[SmsSyncReceiptsJob] synced blast=#{blast.id} updated=#{updated}")
  end

  private

  def syncable_deliveries(blast)
    blast.outreach_deliveries
      .where(provider: "clicksend")
      .where.not(provider_message_id: [ nil, "" ])
      .where.not(status: TERMINAL_STATUSES)
  end

  def sync_batch(deliveries)
    deliveries.count do |delivery|
      sync_delivery(delivery)
    end
  end

  def sync_delivery(delivery)
    result = ClicksendClient.sms_receipt(delivery.provider_message_id)
    return false unless result[:success] && result[:receipt].is_a?(Hash)

    attrs = OutreachDeliveryStatus.normalize_clicksend_receipt(result[:receipt])
    delivery.mark_provider_event!(**attrs, occurred_at: Time.current, metadata: { clicksend_receipt: result[:receipt] })
    true
  rescue StandardError => e
    Rails.logger.error("[SmsSyncReceiptsJob] receipt sync failed for delivery=#{delivery.id}: #{e.class} #{e.message}")
    false
  end
end
