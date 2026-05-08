# frozen_string_literal: true

class SendSmsJob < ApplicationJob
  queue_as :default

  def perform(to:, body:)
    ClicksendClient.send_sms(to: to, body: body)
  end
end
