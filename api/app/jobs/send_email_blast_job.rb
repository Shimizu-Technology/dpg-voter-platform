# frozen_string_literal: true

class SendEmailBlastJob < ApplicationJob
  queue_as :default
  discard_on StandardError # Email sends are not idempotent; retries can duplicate blasts.

  def perform(email_blast_id: nil, subject: nil, body: nil, filters: {}, initiated_by_user_id: nil)
    blast = EmailBlast.find_by(id: email_blast_id) if email_blast_id
    if email_blast_id.present? && blast.nil?
      Rails.logger.warn("[EmailBlast] skipped missing email_blast_id=#{email_blast_id}")
      return
    end

    subject ||= blast&.subject
    body ||= blast&.body
    filters = blast&.filters || filters || {}
    initiated_by_user_id ||= blast&.initiated_by_user_id

    blast&.update!(status: "sending", started_at: Time.current)
    supporters = OutreachRecipientQuery.email_scope(base_scope: Supporter.all, filters: filters)
    blast&.update!(total_recipients: supporters.count)

    result = SupporterEmailService.send_blast(
      subject: subject,
      body_html: body,
      supporters: supporters,
      recorded_by_user_id: initiated_by_user_id,
      email_blast: blast
    )

    blast&.update!(status: "completed", completed_at: Time.current, sent_count: result[:sent], failed_count: result[:failed])
    result[:errors].to_a.each { |error| blast&.append_error(error) }
    Rails.logger.info("[EmailBlast] completed: sent=#{result[:sent]} failed=#{result[:failed]}")
  rescue StandardError => e
    begin
      blast&.update(status: "failed", completed_at: Time.current)
      blast&.append_error("Job error: #{e.message}")
    rescue StandardError => cleanup_error
      Rails.logger.error("[EmailBlast] failed to record job failure after #{e.class}: #{cleanup_error.class} #{cleanup_error.message}")
    end
    Rails.logger.error("[EmailBlast] failed: #{e.class} #{e.message}")
    raise
  end
end
