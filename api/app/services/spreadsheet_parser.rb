# frozen_string_literal: true

require "roo"

class SpreadsheetParser
  # Standard column mappings we try to auto-detect
  COLUMN_PATTERNS = {
    "name" => /\bname\b/i,
    "first_name" => /\bfirst\s*name\b/i,
    "middle_name" => /\bmiddle\s*name\b/i,
    "last_name" => /\blast\s*name\b/i,
    "contact_number" => /\b(contact|phone|cell|mobile|tel)\b.*\b(no|num|number|#)?\b/i,
    "dob" => /\b(d\.?o\.?b\.?|date\s*of\s*birth|birth\s*date|birthday)\b/i,
    "email" => /\b(email|e-mail)\b/i,
    "street_address" => /\b(address|street|residence|location)\b/i,
    "registered_voter" => /\b(registered|voter|reg)\b/i,
    "comments" => /\b(comment|note|remark)\b/i,
    "village" => /\b(village|barangay|municipality)\b/i
  }.freeze

  ParseResult = Data.define(:sheets, :errors)
  SheetInfo = Data.define(:name, :index, :headers, :row_count, :sample_rows)

  # Parse a file and return sheet metadata (no row data yet).
  # Used for step 1: tab selection + column mapping.
  def self.parse_metadata(file_path, original_filename: nil)
    spreadsheet = open_spreadsheet(file_path, original_filename)
    errors = []
    sheets = []

    spreadsheet.sheets.each_with_index do |sheet_name, index|
      spreadsheet.default_sheet = sheet_name
      headers = detect_headers(spreadsheet)
      next if headers.empty?

      row_count = count_data_rows(spreadsheet, headers[:header_row])
      sample = extract_rows(spreadsheet, headers, limit: 5)

      sheets << SheetInfo.new(
        name: sheet_name,
        index: index,
        headers: headers,
        row_count: row_count,
        sample_rows: sample
      )
    end

    errors << "No sheets with data found" if sheets.empty?
    ParseResult.new(sheets: sheets, errors: errors)
  end

  # Parse all rows from a specific sheet with column mapping.
  # Used for step 2: preview with full data.
  def self.parse_rows(file_path, sheet_index:, column_mapping:, original_filename: nil)
    spreadsheet = open_spreadsheet(file_path, original_filename)
    spreadsheet.default_sheet = spreadsheet.sheets[sheet_index]

    # Find header row from mapping
    header_row = column_mapping[:header_row] || 1

    rows = []
    issues = []

    max_rows = 5000
    last_row = spreadsheet.last_row || 0
    total_data_rows = [ last_row - header_row, 0 ].max
    if total_data_rows > max_rows
      return { rows: [], issues: [ "Spreadsheet has #{total_data_rows} rows, exceeding the #{max_rows} row limit. Please split into smaller files." ], total: 0 }
    end

    return { rows: [], issues: [], total: 0 } if last_row < header_row + 1

    ((header_row + 1)..last_row).each do |row_num|
      raw = {}
      column_mapping[:columns].each do |field, col_index|
        next if col_index.nil? || col_index < 1
        raw[field.to_s] = spreadsheet.cell(row_num, col_index)&.to_s&.strip
      end

      # Skip completely empty rows
      next if raw.values.all?(&:blank?)

      parsed = parse_supporter_row(raw, row_num)
      rows << parsed[:data]
      issues.concat(parsed[:issues]) if parsed[:issues].any?
    end

    { rows: rows, issues: issues, total: rows.size }
  end

  class << self
    private

    def open_spreadsheet(file_path, original_filename)
      ext = File.extname(original_filename || file_path).downcase
      case ext
      when ".xlsx"
        Roo::Excelx.new(file_path)
      when ".xls"
        raise ArgumentError, "Legacy .xls format is not supported. Please save as .xlsx and re-upload."
      when ".csv"
        Roo::CSV.new(file_path)
      else
        # Try to detect from content
        Roo::Spreadsheet.open(file_path)
      end
    end

    def detect_headers(spreadsheet)
      return {} if spreadsheet.last_row.nil? || spreadsheet.last_row < 1

      # Scan first 10 rows for a row that looks like a header
      best_row = nil
      best_score = 0
      best_mapping = {}

      (1..[ spreadsheet.last_row, 10 ].min).each do |row_num|
        cols = (1..(spreadsheet.last_column || 0)).map { |c| spreadsheet.cell(row_num, c)&.to_s&.strip }
        mapping = auto_map_columns(cols)
        score = mapping.values.compact.size

        # Must have at least a name/first_name column
        has_name = mapping["name"] || mapping["first_name"]
        if has_name && score > best_score
          best_score = score
          best_row = row_num
          best_mapping = mapping
        end
      end

      return {} unless best_row

      {
        header_row: best_row,
        columns: best_mapping,
        raw_headers: (1..(spreadsheet.last_column || 0)).map { |c| spreadsheet.cell(best_row, c)&.to_s&.strip }
      }
    end

    def auto_map_columns(header_cells)
      mapping = {}
      used_columns = Set.new

      # First pass: exact/priority matches (email before address to avoid "Email Address" → address)
      priority_order = %w[first_name middle_name last_name name contact_number dob email street_address registered_voter village comments]

      priority_order.each do |field|
        pattern = COLUMN_PATTERNS[field]
        next unless pattern

        header_cells.each_with_index do |cell, idx|
          next if cell.blank?
          col_num = idx + 1
          next if used_columns.include?(col_num)

          if cell.match?(pattern)
            # For address, skip if the header also matches email
            next if field == "street_address" && cell.match?(/\bemail\b/i)

            mapping[field] = col_num
            used_columns << col_num
            break
          end
        end
      end

      mapping
    end

    def count_data_rows(spreadsheet, header_row)
      return 0 unless header_row && spreadsheet.last_row

      count = 0
      ((header_row + 1)..spreadsheet.last_row).each do |row_num|
        has_data = (1..(spreadsheet.last_column || 0)).any? do |col|
          val = spreadsheet.cell(row_num, col)&.to_s&.strip
          val.present? && !val.match?(/\A\d{1,3}\z/) # Skip row-number-only rows
        end
        count += 1 if has_data
      end
      count
    end

    def extract_rows(spreadsheet, headers, limit: 5)
      return [] unless headers[:header_row]

      rows = []
      last_row = spreadsheet.last_row || 0
      return [] if last_row < headers[:header_row] + 1

      ((headers[:header_row] + 1)..last_row).each do |row_num|
        break if rows.size >= limit

        raw = {}
        headers[:columns].each do |field, col_index|
          next if col_index.nil?
          raw[field] = spreadsheet.cell(row_num, col_index)&.to_s&.strip
        end

        next if raw.values.all?(&:blank?)
        rows << raw.merge("_row" => row_num)
      end
      rows
    end

    def parse_supporter_row(raw, row_num)
      data = { "_row" => row_num, "_issues" => [], "_skip" => false }

      # Name parsing
      if raw["first_name"].present? && raw["last_name"].present?
        data["first_name"] = raw["first_name"]
        data["middle_name"] = raw["middle_name"] if raw["middle_name"].present?
        data["last_name"] = raw["last_name"]
      elsif raw["name"].present?
        parts = split_name(raw["name"])
        data["first_name"] = parts[:first_name]
        data["middle_name"] = parts[:middle_name] if parts[:middle_name].present?
        data["last_name"] = parts[:last_name]
        data["_issues"] << parts[:couple_note] if parts[:couple_note]
        if parts[:uncertain] && !parts[:couple_note]
          parsed_name = NameParser.combine(
            first_name: parts[:first_name],
            middle_name: parts[:middle_name],
            last_name: parts[:last_name]
          )
          data["_issues"] << "Name auto-split: \"#{raw['name']}\" → \"#{parsed_name}\""
        end
      else
        data["_skip"] = true
        data["_issues"] << "No name found"
      end

      # Phone
      data["contact_number"] = normalize_phone(raw["contact_number"]) if raw["contact_number"].present?
      data["_issues"] << "Missing phone number" if data["contact_number"].blank?

      # DOB
      if raw["dob"].present?
        parsed_dob = parse_dob(raw["dob"])
        if parsed_dob
          data["dob"] = parsed_dob.to_s
          data["_issues"] << "DOB may be incorrect: #{raw['dob']}" if parsed_dob.year < 1920 || parsed_dob > Date.today
        else
          data["_issues"] << "Could not parse DOB: \"#{raw['dob']}\""
          data["dob"] = nil
        end
      end

      # Email
      data["email"] = raw["email"]&.strip&.downcase if raw["email"].present?

      # Address
      data["street_address"] = raw["street_address"] if raw["street_address"].present?

      # Registered voter
      if raw["registered_voter"].present?
        val = raw["registered_voter"].strip.downcase
        data["registered_voter"] = %w[y yes true 1].include?(val)
      end

      # Comments
      data["comments"] = raw["comments"] if raw["comments"].present?

      # Village (passed through for per-row village assignment)
      data["village"] = raw["village"]&.strip if raw["village"].present?

      issues = data["_issues"]
      { data: data, issues: issues.map { |i| { row: row_num, message: i } } }
    end

    def split_name(full_name)
      NameParser.split_supporter_name(full_name)
    end

    def normalize_phone(phone)
      return nil if phone.blank?
      digits = phone.to_s.gsub(/\D/, "")
      # Format as 671-XXX-XXXX if it's a Guam number
      if digits.length == 10 && digits.start_with?("671")
        "#{digits[0..2]}-#{digits[3..5]}-#{digits[6..9]}"
      elsif digits.length == 7
        "671-#{digits[0..2]}-#{digits[3..6]}"
      else
        phone.to_s.strip
      end
    end

    def parse_dob(dob_str)
      str = dob_str.to_s.strip

      # Handle common typos like "1/81948" → "1/8/1948"
      if str =~ %r{\A(\d{1,2})/(\d)(\d{4})\z}
        str = "#{$1}/#{$2}/#{$3}"
      end

      # Try M/D/YYYY, MM/DD/YYYY
      if str =~ %r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z}
        Date.new($3.to_i, $1.to_i, $2.to_i)
      elsif str =~ %r{\A(\d{4})-(\d{1,2})-(\d{1,2})\z}
        Date.new($1.to_i, $2.to_i, $3.to_i)
      else
        Date.parse(str)
      end
    rescue Date::Error, ArgumentError
      nil
    end
  end
end
