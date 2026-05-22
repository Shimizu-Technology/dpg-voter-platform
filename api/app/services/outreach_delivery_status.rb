# frozen_string_literal: true

class OutreachDeliveryStatus
  class << self
    def normalize_clicksend_receipt(receipt)
      status_code = receipt["status_code"].to_s
      status_text = receipt["status_text"].to_s
      error_code = receipt["error_code"].presence
      text = status_text.downcase

      status = if error_code.present? && error_code.to_s != "0"
        "undelivered"
      elsif text.include?("received") || text.include?("delivered") || status_code.start_with?("2")
        "delivered"
      elsif text.include?("pending") || text.include?("queued")
        "sent"
      elsif text.include?("expired") || text.include?("undeliver") || text.include?("failed") || text.include?("reject")
        "undelivered"
      else
        "unknown"
      end

      {
        status: status,
        provider_status_code: status_code.presence,
        provider_status_text: status_text.presence,
        provider_error_code: error_code
      }
    end

    def normalize_resend_event(event_type)
      case event_type.to_s
      when "email.sent" then "sent"
      when "email.delivered" then "delivered"
      when "email.delivery_delayed" then "delivery_delayed"
      when "email.failed" then "failed"
      when "email.bounced" then "bounced"
      when "email.complained" then "complained"
      when "email.suppressed" then "suppressed"
      else "unknown"
      end
    end
  end
end
