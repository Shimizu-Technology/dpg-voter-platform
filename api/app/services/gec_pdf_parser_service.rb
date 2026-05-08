# frozen_string_literal: true

require "csv"
require "tempfile"
require "timeout"

# Parses Guam Election Commission PDF voter lists into normalized rows
# and provides a QA summary before import.
class GecPdfParserService
  Result = Struct.new(:rows, :qa, :warnings, :errors, keyword_init: true)

  HEADER_TEXT = /Guam Election Commission\s*Voter Listing\s*as of\s*.+?\s*REG\. NO\.\s*NAME\s*(?:ADDRESS\s*)?BIRTH YEAR\s*PCT/i
  PARSE_TIMEOUT_SECONDS = 10
  PREVIEW_TIMEOUT_SECONDS = 3
  PREVIEW_MAX_PAGES = 3
  PREVIEW_MAX_ROWS = 200
  MAX_ADDRESS_CHARS = 150
  REVIEW_MIN_ROWS = 10_000 # Guam full-list imports are ~60k+ rows; below this is likely partial/test data
  FAIL_MIN_ROWS = 1_000
  PCT_REGEX = "\\d{1,2}[A-Z]?".freeze
  ZIP_REGEX = "\\d{5}(?:-\\d{4})?".freeze
  GENERIC_POSTAL_REGEX = "[A-Z0-9\\-]{4,16}".freeze
  LEGACY_ADDRESS_PREFIXES = "ROUTE|BLDG|BUILDING|UNIT|APT|APARTMENT".freeze
  ADDRESS_START_STR = "(?:P[O0] BOX|P\\.[O0]\\. BOX|PMB(?:\\s*\\d+)?\\b|C\\/O|(?:A|F|D)PO\\b|(?:H\\s*C\\s*-?\\s*\\d+|HC-?\\d+)\\s+BOX\\b|#\\s*\\d+[A-Z]?\\b|\\d+[A-Z]?\\s+[A-Z0-9]|(?:#{LEGACY_ADDRESS_PREFIXES})\\b)".freeze
  NAME_TEXT_STR = "([A-Z][A-Z,\\.\\-\\'\\(\\)\\s]{2,80}?)".freeze
  ADDRESS_TEXT_STR = "([A-Z0-9 #,\\.\\-\\/\\'\\&\\(\\)]{3,#{MAX_ADDRESS_CHARS}}?)".freeze

  # Sorted longest-first so Regexp.union matches greedily (e.g. "AGANA HEIGHTS" before "AGANA HTS")
  VILLAGE_ALT_STR = [
    "AGANA HEIGHTS", "AGANA HTS", "ASAN-MAINA", "ASAN MAINA",
    "CHALAN PAGO/ORDOT", "CHALAN PAGO", "ORDOT",
    # GEC PDFs sometimes emit the combined village and sometimes only one component.
    "MONGMONG/TOTO/MAITE", "MONGMONG TOTO MAITE", "MONGMONG", "TOTO", "MAITE", "MTM",
    "SANTA RITA-SUMAI", "SANTA RITA", "TALOFOFO",
    "HAGATNA", "HAGAT", "AGAT", "DEDEDO", "BARRIGADA", "MANGILAO", "SINAJANA",
    "TAMUNING", "YIGO", "YONA", "PITI", "HUMATAK", "MALESSO",
    "UMATAC", "MERIZO", "ASAN", "INALAHAN", "INARAJAN", "GMF", "TUMON"
  ].sort_by { |v| -v.length }.map { |v| Regexp.escape(v) }.join("|")
  VILLAGE_TOKEN_STR = "(?:#{VILLAGE_ALT_STR})\\b".freeze
  VILLAGE_ALT_REGEX = Regexp.new(VILLAGE_ALT_STR)

  # Current GEC export format (line-based): page_no reg_no name address village dob pct ...
  LINE_REGEX = Regexp.new(
    "^\\s*\\d+\\s+(\\d{4,7})\\s+" \
    "#{NAME_TEXT_STR}\\s{2,}" \
    "#{ADDRESS_TEXT_STR}\\s+" \
    "(#{VILLAGE_TOKEN_STR})\\s+" \
    "(\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})\\s+" \
    "(#{PCT_REGEX})\\b"
  )

  # Legacy export often comes one voter per line with ZIP and birth year only.
  LEGACY_LINE_REGEX = Regexp.new(
    "^\\s*(?:\\d+\\s+)?(\\d{4,7})\\s+" \
    "#{NAME_TEXT_STR}(?=\\s+#{ADDRESS_START_STR}|\\s+#{VILLAGE_TOKEN_STR})" \
    "#{ADDRESS_TEXT_STR}\\s+" \
    "(?:(#{VILLAGE_TOKEN_STR})\\s+)?" \
    "#{ZIP_REGEX}\\s+" \
    "(19\\d{2}|20\\d{2})\\s+" \
    "(#{PCT_REGEX})\\b"
  )

  # Legacy format fallback: REG_NO NAME ADDRESS VILLAGE 96XXX BIRTH_YEAR PCT
  ROW_REGEX = Regexp.new(
    "(\\d{4,7})\\s+" \
    "#{NAME_TEXT_STR}(?=\\s+#{ADDRESS_START_STR}|\\s+#{VILLAGE_TOKEN_STR})" \
    "#{ADDRESS_TEXT_STR}\\s+" \
    "(?:(#{VILLAGE_TOKEN_STR})\\s+)?" \
    "#{ZIP_REGEX}\\s+" \
    "(19\\d{2}|20\\d{2})\\s+" \
    "(#{PCT_REGEX})(?=\\s+\\d{4,7}|$)"
  )

  def initialize(file_path:, progress_callback: nil)
    @file_path = file_path
    @progress_callback = progress_callback
    @warnings = []
    @errors = []
  end

  def parse
    parse_internal(
      max_pages: nil,
      max_rows: nil,
      timeout_seconds: PARSE_TIMEOUT_SECONDS,
      preview_mode: false
    )
  end

  def parse_preview_sample(max_pages: PREVIEW_MAX_PAGES, max_rows: PREVIEW_MAX_ROWS)
    parse_internal(
      max_pages: max_pages,
      max_rows: max_rows,
      timeout_seconds: PREVIEW_TIMEOUT_SECONDS,
      preview_mode: true
    )
  end

  def write_normalized_csv(rows)
    tf = Tempfile.new([ "gec_pdf_normalized", ".csv" ])
    begin
      CSV.open(tf.path, "w", encoding: "UTF-8") do |csv|
        csv << [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ]
        rows.each { |r| csv << [ r["name"], r["village"], r["voter_registration_number"], r["dob"], r["dob_estimated"], r["birth_year"], r["pct"], r["address"] ] }
      end
      tf.close
      tf
    rescue StandardError
      tf.close!
      raise
    end
  end

  private

  def parse_internal(max_pages:, max_rows:, timeout_seconds:, preview_mode:)
    reader = PDF::Reader.new(@file_path)
    rows = []
    seen = {}
    pages_processed = 0
    page_count = reader.page_count

    report_progress(pages_processed: 0, page_count: page_count, preview_mode: preview_mode)

    reader.pages.each do |page|
      break if max_pages.present? && pages_processed >= max_pages

      begin
        Timeout.timeout(timeout_seconds) do
          text = page.text.to_s
          next if text.blank?

          pages_processed += 1
          report_progress(pages_processed: pages_processed, page_count: page_count, preview_mode: preview_mode)
          matched_rows = 0

          # 1) Primary parser: modern line-based export
          text.each_line do |line|
            compact = normalize_pdf_line(line)
            next if compact.blank?

            m = compact.match(LINE_REGEX)
            if m
              reg_no, name_raw, address_raw, village_raw, dob_raw, pct = m.captures
              birth_year = normalize_birth_year_from_dob(dob_raw)

              name = normalize_name(name_raw)
              next if name.blank? || name.start_with?("REG.")

              key = [ reg_no, name, village_raw, pct ].join("|")
              next if seen[key]

              seen[key] = true
              matched_rows += 1
              rows << {
                "name" => name,
                "village" => village_raw,
                "voter_registration_number" => reg_no,
                "dob" => dob_raw,
                "dob_estimated" => true,
                "birth_year" => birth_year,
                "pct" => pct,
                "address" => normalize_text(address_raw)
              }

              break if max_rows.present? && rows.size >= max_rows
              next
            end

            legacy_row = parse_legacy_line(compact)
            next unless legacy_row

            key = [ legacy_row["voter_registration_number"], legacy_row["name"], legacy_row["village"], legacy_row["pct"] ].join("|")
            next if seen[key]

            seen[key] = true
            matched_rows += 1
            rows << legacy_row

            break if max_rows.present? && rows.size >= max_rows
          end

          # 2) Last-resort parser: legacy flattened format
          if matched_rows.zero? && (!max_rows.present? || rows.size < max_rows)
            flat = text.gsub("\n", " ")
            flat = flat.gsub(HEADER_TEXT, " ")
            flat = flat.gsub(/\s+/, " ").strip
            next unless flat.match?(/\b96\d{3}\b/)

            flat.scan(ROW_REGEX) do |reg_no, name_raw, address_raw, village_raw, birth_year, pct|
              name = normalize_name(name_raw)
              next if name.blank? || name.start_with?("REG.")

              key = [ reg_no, name, village_raw, pct ].join("|")
              next if seen[key]

              seen[key] = true
              rows << {
                "name" => name,
                "village" => detect_known_village_name(village_raw),
                "voter_registration_number" => reg_no,
                "dob" => birth_year_to_dob_placeholder(birth_year),
                "dob_estimated" => true,
                "birth_year" => birth_year,
                "pct" => pct,
                "address" => normalize_text(address_raw)
              }

              break if max_rows.present? && rows.size >= max_rows
            end
          end
        end
      rescue Timeout::Error
        if preview_mode
          @warnings << "Preview skipped a slow page. Full validation will run during import."
          next
        end
        @errors << "PDF page parsing timed out (possible malformed layout)"
        break
      rescue StandardError => e
        @warnings << "Skipped page due to error: #{e.class}: #{e.message}"
        next
      end

      break if max_rows.present? && rows.size >= max_rows
    end

    report_progress(pages_processed: pages_processed, page_count: page_count, preview_mode: preview_mode)

    qa = if preview_mode
      build_preview_qa(rows, page_count, pages_processed, max_pages, max_rows)
    else
      build_qa(rows, page_count)
    end
    warn_if_low_quality(qa) unless preview_mode

    Result.new(rows: rows, qa: qa, warnings: @warnings, errors: @errors)
  rescue StandardError => e
    @errors << e.message
    Result.new(rows: [], qa: {}, warnings: @warnings, errors: @errors)
  end

  def normalize_name(value)
    v = normalize_text(value)
    v.gsub(/\s+/, " ")
  end

  def normalize_pdf_line(value)
    line = normalize_text(value).upcase
    line = line.gsub(/\bPMB(?=\d)/, "PMB ")
    line = line.gsub(/\bH\s+C\s*(\d+\s+BOX)\b/, 'HC\1')
    line = line.gsub(/\b([NSEW])MARINE\b/, '\1 MARINE')
    line = line.gsub(/\bHÃƒGAT\b/, "HAGAT")
    line = line.gsub(/\bHAGÃ…TÃ‘A\b/, "HAGATNA")
    line = line.gsub(/\b([A-Z])(?=\d{1,4}[A-Z]?\s+(?:MALAC|ANACO|OCEANVIEW|CAPSTAN|TAITANO|CROSS|[A-Z]+(?:\s+[A-Z]+){0,2}\s(?:RD|ROAD|DR|ST|STREET|AVE|AVENUE|LN|LANE|CIRCLE|CT|PL)))/, '\1 ')
    line
  end

  def normalize_text(value)
    value.to_s.gsub(/\s+/, " ").strip
  end

  def parse_legacy_line(line)
    match = line.match(LEGACY_LINE_REGEX)
    match ||= line.match(generic_legacy_line_regex)
    return build_legacy_row(match.captures) if match

    parse_unmatched_line_fallback(line)
  end

  def generic_legacy_line_regex
    @generic_legacy_line_regex ||= Regexp.new(
      "^\\s*(?:\\d+\\s+)?(\\d{4,7})\\s+" \
      "#{NAME_TEXT_STR}(?=\\s+#{ADDRESS_START_STR})" \
      "#{ADDRESS_TEXT_STR}\\s+" \
      "([A-Z][A-Z\\-\\'\\/\\.\\s]{2,60}?)\\s+" \
      "#{GENERIC_POSTAL_REGEX}\\s+" \
      "(19\\d{2}|20\\d{2})\\s+" \
      "(#{PCT_REGEX})\\b"
    )
  end

  def build_legacy_row(captures)
    reg_no, name_raw, address_raw, village_raw, birth_year, pct = captures
    name = normalize_name(name_raw)
    return nil if name.blank? || name.start_with?("REG.")

    {
      "name" => name,
      "village" => detect_known_village_name(village_raw),
      "voter_registration_number" => reg_no,
      "dob" => birth_year_to_dob_placeholder(birth_year),
      "dob_estimated" => true,
      "birth_year" => birth_year,
      "pct" => pct,
      "address" => normalize_text(address_raw)
    }
  end

  def parse_unmatched_line_fallback(line)
    match = line.match(/^\s*(?:\d+\s+)?(\d{4,7})\s+(.+?)\s+(19\d{2}|20\d{2})\s+(#{PCT_REGEX})\s*$/)
    return nil unless match

    reg_no, body, birth_year, pct = match.captures
    body = body.sub(/\s+[A-Z0-9\-]{4,16}\z/, "").strip
    return nil unless body.include?(",")

    last_part, rest = body.split(",", 2).map(&:strip)
    return nil if last_part.blank? || rest.blank?

    tokens = rest.split(/\s+/)
    split_index = tokens.index do |token|
      token.match?(/\d/) || generic_address_starter?(token)
    end
    return nil unless split_index

    given_names = tokens.first(split_index).join(" ").strip
    remainder = tokens.drop(split_index).join(" ").strip
    return nil if given_names.blank? || remainder.blank?

    village = extract_village_from_remainder(remainder)
    address = if village.present?
      remainder.sub(/\b#{Regexp.escape(village)}\b.*\z/, "").strip
    else
      remainder
    end

    build_legacy_row([ reg_no, "#{last_part}, #{given_names}", address, village, birth_year, pct ])
  end

  def generic_address_starter?(token)
    token.match?(/\A(?:#|PO|P0|PMB|HC|BOX|C\/O|USS|VIA|WATERS|UNIT|APO|FPO|DPO)\z/)
  end

  def extract_village_from_remainder(remainder)
    normalized = normalize_text(remainder).upcase
    match = normalized.to_enum(:scan, VILLAGE_ALT_REGEX).map { Regexp.last_match[0] }.last
    detect_known_village_name(match)
  end

  def detect_known_village_name(value)
    raw = normalize_text(value).upcase
    return nil if raw.blank?

    case raw
    when /\bHAGATNA\b/
      "HAGATNA"
    when /\b(?:HAGAT|AGAT|HÃƒGAT)\b/
      "AGAT"
    else
      raw[VILLAGE_ALT_REGEX]
    end
  end

  # Importer currently expects dob-like values. We use Jan 1 placeholder by birth year.
  def birth_year_to_dob_placeholder(year)
    return nil if year.blank?

    "01/01/#{year}"
  end

  def normalize_birth_year_from_dob(dob_raw)
    year = dob_raw.to_s.split("/").last.to_s.strip
    return year unless year.length == 2

    # Guam voter files can include younger voters with 2-digit years; use a moving cutoff.
    current_2_digit_year = Time.zone.now.year % 100
    year_i = year.to_i
    year_i <= current_2_digit_year ? "20#{year}" : "19#{year}"
  end

  def build_qa(rows, page_count)
    return {
      page_count: page_count,
      row_count: 0,
      quality_score: 0,
      missing_name: 0,
      missing_village: 0,
      missing_reg: 0,
      top_villages: {},
      status: "fail"
    } if rows.empty?

    villages = rows.group_by { |r| r["village"] }.transform_values(&:count)
    missing_name = rows.count { |r| r["name"].blank? }
    missing_village = rows.count { |r| r["village"].blank? }
    missing_reg = rows.count { |r| r["voter_registration_number"].blank? }

    score = 100
    score -= 35 if rows.size < REVIEW_MIN_ROWS
    score -= 65 if rows.size < FAIL_MIN_ROWS

    missing_ratio = (missing_name + missing_village + missing_reg).to_f / rows.size
    score -= 20 if missing_ratio > 0.05

    # Keep partial datasets (FAIL_MIN_ROWS..REVIEW_MIN_ROWS-1) in REVIEW band;
    # missing-field penalties should not silently promote them to FAIL.
    if rows.size >= FAIL_MIN_ROWS && rows.size < REVIEW_MIN_ROWS
      score = [ score, 60 ].max
    end

    {
      page_count: page_count,
      row_count: rows.size,
      quality_score: score.clamp(0, 100),
      missing_name: missing_name,
      missing_village: missing_village,
      missing_reg: missing_reg,
      top_villages: villages.sort_by { |_k, v| -v }.first(10).to_h,
      status: score >= 80 ? "pass" : (score >= 60 ? "review" : "fail")
    }
  end

  def build_preview_qa(rows, page_count, pages_processed, max_pages, max_rows)
    {
      page_count: page_count,
      pages_sampled: pages_processed,
      row_count: rows.size,
      quality_score: nil,
      missing_name: rows.count { |r| r["name"].blank? },
      missing_village: rows.count { |r| r["village"].blank? },
      missing_reg: rows.count { |r| r["voter_registration_number"].blank? },
      top_villages: rows.group_by { |r| r["village"] }.transform_values(&:count).sort_by { |_k, v| -v }.first(10).to_h,
      status: "preview",
      preview_mode: true,
      note: "Sample preview only. Full PDF validation runs during import.",
      sample_limited: (max_pages.present? && page_count > max_pages) || (max_rows.present? && rows.size >= max_rows)
    }
  end

  def warn_if_low_quality(qa)
    if qa[:status] == "review"
      @warnings << "Parser quality is REVIEW. Manual sample verification required before import."
    elsif qa[:status] == "fail"
      @warnings << "Parser quality is FAIL. Do not import this PDF directly."
    end
  end

  def report_progress(pages_processed:, page_count:, preview_mode:)
    return if preview_mode
    return unless @progress_callback

    @progress_callback.call(
      pages_processed: pages_processed,
      page_count: page_count
    )
  rescue StandardError => e
    Rails.logger.warn("GecPdfParserService progress callback failed: #{e.class}: #{e.message}")
  end
end
