# frozen_string_literal: true

class SendEmailBlastJob < ApplicationJob
  queue_as :default

  def perform(subject:, body:, filters: {})
    supporters = Supporter.active
                          .where.not(email: [ nil, "" ])
                          .where(opt_in_email: true)

    supporters = supporters.where(village_id: filters["village_id"]) if filters["village_id"].present?
    supporters = supporters.where(motorcade_available: true) if filters["motorcade_available"] == "true"
    supporters = supporters.where(registered_voter: true) if filters["registered_voter"] == "true"
    supporters = supporters.where(yard_sign: true) if filters["yard_sign"] == "true"

    result = SupporterEmailService.send_blast(
      subject: subject,
      body_html: body,
      supporters: supporters
    )

    Rails.logger.info("[EmailBlast] completed: sent=#{result[:sent]} failed=#{result[:failed]}")
  end
end
