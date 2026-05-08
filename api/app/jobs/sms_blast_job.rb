# frozen_string_literal: true

class SmsBlastJob < ApplicationJob
  queue_as :default
  discard_on StandardError # Override parent retry — re-running would duplicate SMS sends

  BATCH_SIZE = 500 # ClickSend supports up to 1000, use 500 for safety
  BATCH_DELAY = 1.0 # seconds between batches to respect rate limits

  def perform(sms_blast_id:)
    blast = SmsBlast.find_by(id: sms_blast_id)
    return unless blast

    blast.update!(status: "sending", started_at: Time.current)

    supporters = build_scope(blast.filters || {})
    total = supporters.count
    blast.update!(total_recipients: total)

    if total.zero?
      blast.update!(status: "completed", completed_at: Time.current, sent_count: 0, failed_count: 0)
      return
    end

    sent_total = 0
    failed_total = 0

    # Process in batches
    supporters.find_in_batches(batch_size: BATCH_SIZE).with_index do |batch, batch_idx|
      # Rate limit between batches (sleep before batches 2+)
      sleep(BATCH_DELAY) if batch_idx > 0

      phones_and_bodies = batch.filter_map do |supporter|
        next if supporter.contact_number.blank?
        { to: supporter.contact_number, body: blast.message }
      end

      next if phones_and_bodies.empty?

      result = ClicksendClient.send_batch(phones_and_bodies)

      sent_total += result[:sent]
      failed_total += result[:failed]

      # Update progress in DB (absolute counts from running totals)
      SmsBlast.where(id: blast.id).update_all(
        [ "sent_count = ?, failed_count = ?", sent_total, failed_total ]
      )

      # Log failures
      result[:results].select { |r| !r[:success] }.each do |failure|
        blast.append_error("#{failure[:to]}: #{failure[:error]}")
      end
    end

    blast.update!(status: "completed", completed_at: Time.current)

  rescue StandardError => e
    Rails.logger.error("[SmsBlastJob] Failed: #{e.message}")
    blast&.update(status: "failed", completed_at: Time.current)
    blast&.append_error("Job error: #{e.message}")
  end

  private

  def build_scope(filters)
    supporters = Supporter.active
      .where.not(contact_number: [ nil, "" ])
      .where("TRIM(contact_number) != ''")
      .where(opt_in_text: true)
    supporters = supporters.where(village_id: filters["village_id"]) if filters["village_id"].present?
    supporters = supporters.where(motorcade_available: true) if filters["motorcade_available"] == "true"
    supporters = supporters.where(registered_voter: true) if filters["registered_voter"] == "true"
    supporters = supporters.where(yard_sign: true) if filters["yard_sign"] == "true"
    supporters
  end
end
