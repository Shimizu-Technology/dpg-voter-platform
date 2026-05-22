# frozen_string_literal: true

class SmsSyncReceiptsJob < ApplicationJob
  queue_as :default

  def perform(sms_blast_id:)
    blast = SmsBlast.find_by(id: sms_blast_id)
    return unless blast

    updated = 0
    blast.outreach_deliveries.where(provider: "clicksend").where.not(provider_message_id: [ nil, "" ]).find_each do |delivery|
      result = ClicksendClient.sms_receipt(delivery.provider_message_id)
      next unless result[:success] && result[:receipt].is_a?(Hash)

      attrs = OutreachDeliveryStatus.normalize_clicksend_receipt(result[:receipt])
      delivery.mark_provider_event!(**attrs, occurred_at: Time.current, metadata: { clicksend_receipt: result[:receipt] })
      updated += 1
    rescue StandardError => e
      Rails.logger.error("[SmsSyncReceiptsJob] receipt sync failed for delivery=#{delivery.id}: #{e.class} #{e.message}")
    end

    Rails.logger.info("[SmsSyncReceiptsJob] synced blast=#{blast.id} updated=#{updated}")
  end
end
