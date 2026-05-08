# frozen_string_literal: true

class SendWelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(supporter_id:)
    supporter = Supporter.find_by(id: supporter_id)
    return unless supporter

    SupporterEmailService.send_welcome(supporter)
  end
end
