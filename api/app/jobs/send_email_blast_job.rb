# frozen_string_literal: true

class SendEmailBlastJob < ApplicationJob
  queue_as :default
  discard_on StandardError # Email sends are not idempotent; retries can duplicate blasts.

  def perform(subject:, body:, filters: {}, initiated_by_user_id: nil)
    supporters = OutreachRecipientQuery.email_scope(base_scope: Supporter.all, filters: filters)

    result = SupporterEmailService.send_blast(
      subject: subject,
      body_html: body,
      supporters: supporters,
      recorded_by_user_id: initiated_by_user_id
    )

    Rails.logger.info("[EmailBlast] completed: sent=#{result[:sent]} failed=#{result[:failed]}")
  end
end
