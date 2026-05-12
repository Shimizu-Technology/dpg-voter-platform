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
        { to: supporter.contact_number, body: blast.message, supporter_id: supporter.id }
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

      begin
        log_contact_attempts!(batch, phones_and_bodies, result[:results], blast)
      rescue StandardError => e
        Rails.logger.error("[SmsBlastJob] Failed to log contact attempts for blast #{blast.id}: #{e.message}")
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
    OutreachRecipientQuery.sms_scope(base_scope: Supporter.all, filters: filters)
  end

  def log_contact_attempts!(supporters, phones_and_bodies, result_rows, blast)
    return if blast.initiated_by_user_id.blank?

    messages_by_phone = phones_and_bodies.each_with_object({}) do |message, memo|
      key = normalized_phone_key(message[:to])
      memo[key] ||= []
      memo[key] << message
    end

    result_rows_by_supporter_id = result_rows.each_with_object({}) do |row, memo|
      supporter_id = row[:supporter_id] || messages_by_phone[normalized_phone_key(row[:to])]&.shift&.dig(:supporter_id)
      memo[supporter_id] = row if supporter_id
    end
    now = Time.current

    attempts = supporters.filter_map do |supporter|
      result = result_rows_by_supporter_id[supporter.id]
      next unless result

      {
        supporter_id: supporter.id,
        recorded_by_user_id: blast.initiated_by_user_id,
        channel: "sms",
        outcome: result[:success] ? "attempted" : "unavailable",
        note: contact_attempt_note(blast, result),
        recorded_at: now,
        created_at: now,
        updated_at: now
      }
    end

    SupporterContactAttempt.insert_all!(attempts) if attempts.any?
  end

  def normalized_phone_key(phone)
    phone.to_s.gsub(/\D/, "").sub(/\A1(?=\d{10}\z)/, "")
  end

  def contact_attempt_note(blast, result)
    prefix = result[:success] ? "SMS blast queued/sent" : "SMS blast failed"
    suffix = result[:message_id].present? ? " Provider ID: #{result[:message_id]}." : ""
    error = result[:error].present? ? " Error: #{result[:error]}." : ""
    "#{prefix}: #{blast.message.to_s.truncate(120)}#{suffix}#{error}"
  end
end
