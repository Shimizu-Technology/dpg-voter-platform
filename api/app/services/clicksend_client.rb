# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"

class ClicksendClient
  BASE_URL = "https://rest.clicksend.com/v3"

  class << self
    def send_sms(to:, body:, from: nil)
      username = ENV["CLICKSEND_USERNAME"]
      api_key  = ENV["CLICKSEND_API_KEY"]
      from   ||= ENV["CLICKSEND_SENDER_ID"] || "JT2026"

      if username.blank? || api_key.blank?
        Rails.logger.error("[ClicksendClient] Missing credentials — SMS not sent")
        return { success: false, error: "missing_credentials" }
      end

      # Truncate sender ID to ClickSend's 11-char limit
      from = from[0...11] if from.length > 11

      # E.164 format
      formatted_to = to.strip
      formatted_to = "+1#{formatted_to}" if formatted_to.match?(/\A\d{10}\z/)
      formatted_to = "+#{formatted_to}" unless formatted_to.start_with?("+")

      # ClickSend doesn't like $ signs
      encoded_body = body.gsub("$", "USD ")

      payload = {
        messages: [
          {
            source: "campaign_tracker",
            from: from,
            body: encoded_body,
            to: formatted_to
          }
        ]
      }

      Rails.logger.info("[ClicksendClient] Sending SMS to #{mask_phone(formatted_to)} (#{encoded_body.length} chars)")

      auth = Base64.strict_encode64("#{username}:#{api_key}")
      uri  = URI("#{BASE_URL}/sms/send")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.request_uri, {
        "Authorization" => "Basic #{auth}",
        "Content-Type"  => "application/json"
      })
      request.body = payload.to_json

      begin
        response = http.request(request)
      rescue StandardError => e
        Rails.logger.error("[ClicksendClient] HTTP error: #{e.message}")
        return { success: false, error: e.message }
      end

      if response.code.to_i == 200
        json = JSON.parse(response.body) rescue {}
        if json["response_code"] == "SUCCESS"
          message_id = json.dig("data", "messages", 0, "message_id") rescue "unknown"
          Rails.logger.info("[ClicksendClient] Sent SMS to #{mask_phone(formatted_to)} — ID: #{message_id}")
          { success: true, message_id: message_id }
        else
          Rails.logger.error("[ClicksendClient] API error: #{json['response_code']} — #{json['response_msg']}")
          { success: false, error: json["response_code"] }
        end
      else
        Rails.logger.error("[ClicksendClient] HTTP #{response.code}: #{response.body}")
        { success: false, error: "http_#{response.code}" }
      end
    end

    # Send up to 1000 messages in a single API call.
    # phones_and_bodies: array of { to:, body: } hashes
    # Returns { results: [{ to:, success:, message_id:, error: }], sent: N, failed: N }
    def send_batch(phones_and_bodies, from: nil)
      username = ENV["CLICKSEND_USERNAME"]
      api_key  = ENV["CLICKSEND_API_KEY"]
      from   ||= ENV["CLICKSEND_SENDER_ID"] || "JT2026"

      if username.blank? || api_key.blank?
        Rails.logger.error("[ClicksendClient] Missing credentials — batch not sent")
        return {
          results: phones_and_bodies.map { |m| { to: m[:to], success: false, message_id: nil, error: "missing_credentials" } },
          sent: 0,
          failed: phones_and_bodies.size
        }
      end

      from = from[0...11] if from.length > 11

      messages = phones_and_bodies.map do |item|
        formatted_to = item[:to].strip
        formatted_to = "+1#{formatted_to}" if formatted_to.match?(/\A\d{10}\z/)
        formatted_to = "+#{formatted_to}" unless formatted_to.start_with?("+")

        {
          source: "campaign_tracker",
          from: from,
          body: item[:body].gsub("$", "USD "),
          to: formatted_to
        }
      end

      Rails.logger.info("[ClicksendClient] Sending batch of #{messages.size} SMS")

      auth = Base64.strict_encode64("#{username}:#{api_key}")
      uri  = URI("#{BASE_URL}/sms/send")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60 # Longer timeout for batch

      request = Net::HTTP::Post.new(uri.request_uri, {
        "Authorization" => "Basic #{auth}",
        "Content-Type"  => "application/json"
      })
      request.body = { messages: messages }.to_json

      begin
        response = http.request(request)
      rescue StandardError => e
        Rails.logger.error("[ClicksendClient] Batch HTTP error: #{e.message}")
        return { results: messages.map { |m| { to: m[:to], success: false, message_id: nil, error: e.message } }, sent: 0, failed: messages.size }
      end

      sent = 0
      failed = 0
      results = []

      if response.code.to_i == 200
        json = begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          Rails.logger.error("[ClicksendClient] JSON parse error: #{e.message}")
          nil
        end

        if json.nil?
          failed = messages.size
          results = messages.map { |m| { to: m[:to], success: false, message_id: nil, error: "json_parse_error" } }
        else
          api_messages = json.dig("data", "messages") || []

          api_messages.each do |msg|
            success = msg["status"] == "SUCCESS"
            if success
              sent += 1
            else
              failed += 1
            end
            results << {
              to: msg["to"],
              success: success,
              message_id: msg["message_id"],
              error: success ? nil : msg["status"]
            }
          end

          # If API returned fewer results than messages sent, count the gap as failures
          unaccounted = messages.size - (sent + failed)
          if unaccounted > 0
            Rails.logger.warn("[ClicksendClient] #{unaccounted} messages unaccounted for in API response")
            failed += unaccounted
            accounted_tos = results.map { |r| r[:to] }.to_set
            messages.each do |m|
              next if accounted_tos.include?(m[:to])
              results << { to: m[:to], success: false, message_id: nil, error: "unaccounted_in_response" }
            end
          end
        end
      else
        Rails.logger.error("[ClicksendClient] Batch HTTP #{response.code}: #{response.body}")
        failed = messages.size
        results = messages.map { |m| { to: m[:to], success: false, message_id: nil, error: "http_#{response.code}" } }
      end

      Rails.logger.info("[ClicksendClient] Batch complete: #{sent} sent, #{failed} failed")
      { results: results, sent: sent, failed: failed }
    end

    def account_balance
      username = ENV["CLICKSEND_USERNAME"]
      api_key  = ENV["CLICKSEND_API_KEY"]
      return nil if username.blank? || api_key.blank?

      auth = Base64.strict_encode64("#{username}:#{api_key}")
      uri  = URI("#{BASE_URL}/account")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.request_uri, {
        "Authorization" => "Basic #{auth}",
        "Content-Type"  => "application/json"
      })

      response = http.request(request)
      json = JSON.parse(response.body) rescue {}
      json.dig("data", "balance")&.to_f
    rescue StandardError => e
      Rails.logger.error("[ClicksendClient] Balance check failed: #{e.message}")
      nil
    end

    def mask_phone(phone)
      return "unknown" if phone.blank?

      normalized = phone.to_s
      return "****" if normalized.length <= 4

      "#{'*' * (normalized.length - 4)}#{normalized[-4, 4]}"
    end
  end
end
