# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"

# Extracts supporter data from photographed campaign signup forms
# using Gemini 2.5 Flash via OpenRouter.
class FormScanner
  OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
  MODEL = "google/gemini-2.5-flash"

  EXTRACTION_PROMPT = <<~PROMPT
    You are extracting data from a Guam political campaign supporter signup form.
    The form is a physical paper form that has been photographed.
    Fields may be handwritten or printed. Extract what you can read.

    Extract these fields (return null for any field you cannot read):
    - first_name: First/given name
    - middle_name: Middle name(s), initial(s), or additional given name(s)
    - last_name: Last/family name
    - print_name: Full printed name (if first/last not clearly separable)
    - contact_number: Phone number (Guam numbers are typically 671-XXX-XXXX)
    - email: Email address
    - street_address: Street/home address
    - dob: Date of birth (format as YYYY-MM-DD if possible)
    - village: Village name (one of Guam's 19 villages)
    - precinct_number: Precinct number if visible
    - registered_voter: true/false (look for checkmark or Y/N)
    - yard_sign: true/false (wants a yard sign)
    - motorcade_available: true/false (available for motorcade)

    Guam's 19 villages: Agana Heights, Asan-Ma'ina, Barrigada, Chalan Pago/Ordot,
    Dededo, Hågat, Hagåtña, Humåtak, Inalåhan, Malesso', Mangilao,
    Mongmong/Toto/Maite, Piti, Sånta Rita-Sumai, Sinajana, Talo'fo'fo',
    Tamuning, Yigo, Yona.

    Return ONLY valid JSON with two top-level keys: "fields" and "confidence".
    - "fields": object with the extracted values (null for unreadable fields)
    - "confidence": object with the same keys, each a value of "high", "medium", or "low"
      - "high" = clearly legible, very confident
      - "medium" = partially legible or inferred from context
      - "low" = barely legible, guessing

    For boolean fields, use true/false. For unknown fields, use null.
    If you see multiple forms, extract only the first/most prominent one.

    Example response:
    {"fields":{"first_name":"Juan","middle_name":"Santos","last_name":"Cruz","contact_number":"671-555-1234","email":null,"street_address":"123 Marine Corps Dr","dob":"1985-03-15","village":"Tamuning","precinct_number":"17","registered_voter":true,"yard_sign":false,"motorcade_available":true},"confidence":{"first_name":"high","middle_name":"medium","last_name":"high","contact_number":"medium","email":null,"street_address":"high","dob":"low","village":"high","precinct_number":"medium","registered_voter":"high","yard_sign":"high","motorcade_available":"high"}}
  PROMPT

  BATCH_EXTRACTION_PROMPT = <<~PROMPT
    You are extracting multiple supporter rows from a photographed Guam campaign blue signup sheet.
    The image may contain several rows on one page. Extract as many rows as clearly visible.

    Return ONLY valid JSON with this shape:
    {
      "rows": [
        {
          "first_name": "...",
          "middle_name": "...",
          "last_name": "...",
          "contact_number": "...",
          "email": "...",
          "street_address": "...",
          "dob": "YYYY-MM-DD or null",
          "village": "...",
          "registered_voter": true,
          "yard_sign": false,
          "motorcade_available": false,
          "confidence": {
            "first_name": "high|medium|low|null",
            "middle_name": "high|medium|low|null",
            "last_name": "high|medium|low|null",
            "contact_number": "high|medium|low|null",
            "email": "high|medium|low|null",
            "street_address": "high|medium|low|null",
            "dob": "high|medium|low|null",
            "village": "high|medium|low|null"
          }
        }
      ]
    }

    Rules:
    - Extract one JSON row per distinct person on the sheet.
    - Treat each row independently; do not copy values from one row into another.
    - If text is ambiguous, leave that field out rather than guessing from nearby rows.
    - Keep each row compact to avoid truncation:
      - Omit keys that are unknown instead of writing null.
      - Do NOT include keys outside the schema above.
      - Keep text fields short and literal to what is on the form (no commentary, no inferred city/state expansions).
    - Extract email addresses when present in the Email Address column, even if only some rows have them.
    - For checkboxes, use true/false; if unknown, use null.
    - If no rows are readable, return {"rows":[]}.
    - Return minified JSON only (single line, no markdown fences, no explanations).
  PROMPT

  class << self
    def extract(image_data)
      api_key = ENV["OPENROUTER_API_KEY"]
      if api_key.blank?
        return { success: false, error: "OpenRouter API key not configured" }
      end

      # Handle both base64 data and data URLs
      if image_data.start_with?("data:")
        image_url = image_data
      else
        # Assume base64 JPEG if no prefix
        image_url = "data:image/jpeg;base64,#{image_data}"
      end

      payload = {
        model: MODEL,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: EXTRACTION_PROMPT },
              { type: "image_url", image_url: { url: image_url } }
            ]
          }
        ],
        temperature: 0.1,
        max_tokens: 1000
      }

      response = perform_openrouter_request(payload, api_key)
      return response if response[:success] == false

      content = response[:content].to_s
      parsed = parse_json_content(content)
      return parsed if parsed[:success] == false

      payload_data = parsed[:data].is_a?(Hash) ? parsed[:data] : {}

      # Support both new format (fields/confidence) and legacy flat format
      if payload_data.key?("fields")
        extracted = payload_data["fields"]
        confidence = payload_data["confidence"] || {}
      else
        extracted = payload_data
        confidence = {}
      end

      # Normalize village name to match our DB
      extracted["village_id"] = match_village(extracted["village"]) if extracted["village"]

      if extracted["first_name"].blank? && extracted["last_name"].blank? && extracted["print_name"].present?
        parts = split_print_name(extracted["print_name"])
        extracted["first_name"] = parts[:first_name]
        extracted["middle_name"] = parts[:middle_name] if extracted["middle_name"].blank?
        extracted["last_name"] = parts[:last_name]
      end

      { success: true, data: extracted, confidence: confidence, raw_response: content }
    end

    def extract_batch(image_data, default_village_id: nil)
      api_key = ENV["OPENROUTER_API_KEY"]
      if api_key.blank?
        return { success: false, error: "OpenRouter API key not configured" }
      end

      image_url = if image_data.start_with?("data:")
        image_data
      else
        "data:image/jpeg;base64,#{image_data}"
      end

      payload = {
        model: MODEL,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: BATCH_EXTRACTION_PROMPT },
              { type: "image_url", image_url: { url: image_url } }
            ]
          }
        ],
        temperature: 0.05,
        max_tokens: 7000
      }

      response = perform_openrouter_request(payload, api_key)
      return response if response[:success] == false

      content = response[:content].to_s
      parsed = parse_json_content(content)
      return parsed if parsed[:success] == false

      payload_data = parsed[:data].is_a?(Hash) ? parsed[:data] : {}
      rows = payload_data["rows"]
      rows = [ payload_data["fields"] ] if rows.blank? && payload_data.key?("fields")
      rows = [] unless rows.is_a?(Array)

      capped_rows = rows.first(100)
      # Pre-load all villages to avoid N+1 queries in match_village
      all_villages = Village.all.to_a
      village_ids = capped_rows.filter_map { |r| match_village_cached(r["village"].to_s.strip.presence, all_villages) || default_village_id&.to_i }
      village_map = all_villages.index_by(&:id)

      normalized_rows = capped_rows.each_with_index.map do |row, idx|
        normalize_batch_row(row, idx: idx, default_village_id: default_village_id, village_map: village_map, all_villages: all_villages)
      end

      {
        success: true,
        rows: normalized_rows,
        partial_parse: parsed[:partial] == true,
        raw_response: content
      }
    end

    private

    def perform_openrouter_request(payload, api_key)
      uri = URI(OPENROUTER_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 45

      request = Net::HTTP::Post.new(uri.request_uri, {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "HTTP-Referer" => "https://campaign-tracker.shimizu-technology.com",
        "X-Title" => "Campaign Tracker OCR"
      })
      request.body = payload.to_json

      Rails.logger.info("[FormScanner] Sending image to Gemini 2.5 Flash via OpenRouter")

      begin
        response = http.request(request)
      rescue StandardError => e
        Rails.logger.error("[FormScanner] HTTP error: #{e.message}")
        return { success: false, error: e.message }
      end

      return { success: false, error: "API error: #{response.code}", raw_response: response.body } unless response.code.to_i == 200

      begin
        json = JSON.parse(response.body)
      rescue JSON::ParserError => e
        Rails.logger.error("[FormScanner] Failed to parse API response: #{e.message}, body: #{response.body.truncate(500)}")
        return { success: false, error: "Invalid API response format" }
      end
      content = json.dig("choices", 0, "message", "content")
      if content.blank?
        Rails.logger.error("[FormScanner] Empty response from API")
        return { success: false, error: "No data extracted from image" }
      end

      { success: true, content: content }
    end

    def parse_json_content(content)
      clean = content.strip.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")
      parsed = JSON.parse(clean)
      { success: true, data: parsed, partial: false }
    rescue JSON::ParserError => e
      partial_rows = extract_rows_from_partial_json(clean)
      if partial_rows.any?
        Rails.logger.warn("[FormScanner] Parsed partial batch rows after JSON truncation (#{partial_rows.size} rows)")
        return { success: true, data: { "rows" => partial_rows }, partial: true }
      end

      Rails.logger.error("[FormScanner] JSON parse error: #{e.message}, raw: #{content}")
      { success: false, error: "Could not parse extracted data", raw_response: content }
    end

    def extract_rows_from_partial_json(raw)
      rows_key_index = raw.index('"rows"')
      return [] if rows_key_index.nil?

      array_start = raw.index("[", rows_key_index)
      return [] if array_start.nil?

      rows = []
      in_string = false
      escape = false
      depth = 0
      bracket_depth = 0
      current_start = nil
      i = array_start + 1

      while i < raw.length
        ch = raw[i]

        if in_string
          if escape
            escape = false
          elsif ch == "\\"
            escape = true
          elsif ch == '"'
            in_string = false
          end
          i += 1
          next
        end

        if ch == '"'
          in_string = true
          i += 1
          next
        end

        if ch == "{"
          current_start = i if depth.zero?
          depth += 1
        elsif ch == "["
          bracket_depth += 1
        elsif ch == "]"
          break if bracket_depth.zero? && depth.zero?
          bracket_depth -= 1 if bracket_depth.positive?
        elsif ch == "}"
          depth -= 1 if depth.positive?
          if depth.zero? && bracket_depth.zero? && current_start
            object_json = raw[current_start..i]
            begin
              parsed_object = JSON.parse(object_json)
              rows << parsed_object if parsed_object.is_a?(Hash)
            rescue JSON::ParserError
              # Ignore malformed trailing object fragments.
            end
            current_start = nil
          end
        end

        i += 1
      end

      rows
    end

    def normalize_batch_row(row, idx:, default_village_id:, village_map: {}, all_villages: [])
      source = row.is_a?(Hash) ? row : {}
      confidence = source["confidence"].is_a?(Hash) ? source["confidence"] : {}
      village_name = source["village"].to_s.strip
      village_id = match_village_cached(village_name.presence, all_villages) || default_village_id&.to_i
      issues = []
      issues << "Village missing" if village_id.blank?

      first_name = source["first_name"].to_s.strip
      middle_name = source["middle_name"].to_s.strip.presence
      last_name = source["last_name"].to_s.strip
      if first_name.blank? && last_name.blank? && source["print_name"].present?
        parts = split_print_name(source["print_name"].to_s)
        first_name = parts[:first_name]
        middle_name = parts[:middle_name]
        last_name = parts[:last_name]
      end

      issues << "First name missing" if first_name.blank?
      issues << "Last name missing" if last_name.blank?
      issues << "Phone missing" if source["contact_number"].to_s.strip.blank?

      {
        "_row" => idx + 1,
        "_skip" => false,
        "_issues" => issues,
        "first_name" => first_name,
        "middle_name" => middle_name,
        "last_name" => last_name,
        "contact_number" => source["contact_number"].to_s.strip,
        "email" => source["email"].to_s.strip.presence,
        "street_address" => source["street_address"].to_s.strip.presence,
        "dob" => source["dob"].to_s.strip.presence,
        "village_id" => village_id,
        "village_name" => village_id.present? ? village_map[village_id]&.name : village_name.presence,
        "registered_voter" => normalize_boolean(source["registered_voter"], fallback: true),
        "yard_sign" => normalize_boolean(source["yard_sign"], fallback: false),
        "motorcade_available" => normalize_boolean(source["motorcade_available"], fallback: false),
        "opt_in_text" => normalize_boolean(source["opt_in_text"], fallback: false),
        "opt_in_email" => normalize_boolean(source["opt_in_email"], fallback: false),
        "confidence" => confidence
      }
    end

    def split_print_name(print_name)
      NameParser.split_print_name(print_name)
    end

    def normalize_boolean(value, fallback:)
      return fallback if value.nil?
      return value if value == true || value == false

      normalized = value.to_s.strip.downcase
      return true if %w[true yes y 1 checked].include?(normalized)
      return false if %w[false no n 0 unchecked].include?(normalized)

      fallback
    end

    # In-memory village matching — no DB queries
    def match_village_cached(name, all_villages)
      return nil if name.blank?

      downcased = name.downcase.strip
      # Exact match
      village = all_villages.find { |v| v.name.downcase == downcased }
      return village.id if village

      # Partial match — require at least 4 chars and prefer starts_with to avoid short-string mismatches.
      # Also require the query covers at least 40% of the village name to prevent "Rita" matching "Sånta Rita-Sumai".
      if downcased.length >= 4
        village = all_villages.find { |v| v.name.downcase.start_with?(downcased) }
        village ||= all_villages.find { |v|
          vname = v.name.downcase
          vname.include?(downcased) && downcased.length >= (vname.length * 0.4)
        }
        return village.id if village
      end

      nil
    end

    # DB-based match (used by single-form extract)
    def match_village(name)
      return nil if name.blank?

      # Try exact match first, then fuzzy
      village = Village.find_by("LOWER(name) = ?", name.downcase.strip)
      return village.id if village

      # Partial match — require minimum length to avoid mismatches
      sanitized = ActiveRecord::Base.sanitize_sql_like(name.downcase.strip)
      return nil if sanitized.length < 4

      village = Village.where("LOWER(name) LIKE ?", "%#{sanitized}%").first
      village&.id
    end
  end
end
