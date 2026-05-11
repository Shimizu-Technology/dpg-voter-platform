# frozen_string_literal: true

# Parses and imports GEC voter registration lists (Excel format).
# Handles DOB month/day swap detection and village resolution.
class GecImportService
  REQUIRED_COLUMNS = %w[first_name last_name].freeze  # May be satisfied by combined_name
  OPTIONAL_COLUMNS = %w[middle_name dob birth_year village voter_registration_number dob_estimated address precinct_number].freeze
  MAX_STORED_ROW_ERRORS = 50

  # Column name aliases to handle different GEC Excel formats
  COLUMN_ALIASES = {
    "first_name" => [ "first_name", "first name", "fname", "given_name", "given name" ],
    "middle_name" => [ "middle_name", "middle name", "mname" ],
    "last_name" => [ "last_name", "last name", "lname", "surname", "family_name", "family name" ],
    # GEC official format: combined "NAME" column in "LAST, FIRST MIDDLE" format
    "combined_name" => [ "name" ],
    "dob" => [ "dob", "date_of_birth", "date of birth", "birth_date", "birth date", "birthday" ],
    # GEC now provides year of birth only (no full DOB) — support both formats
    "birth_year" => [ "birth_year", "year_of_birth", "year of birth", "yob", "birth year", "birthyear" ],
    "dob_estimated" => [ "dob_estimated", "dob estimated", "birth_year_only", "birth year only" ],
    "village" => [ "village", "municipality", "district", "precinct_village", "voting_district" ],
    "address" => [ "address", "street_address", "street address", "mailing_address", "mailing address", "residence_address" ],
    "precinct_number" => [ "precinct_number", "precinct number", "precinct", "pct", "pct." ],
    "voter_registration_number" => [ "voter_registration_number", "voter_reg", "registration_number",
                                     "reg_no", "reg_number", "vrn", "reg._no.", "reg.no.", "reg._no" ]
  }.freeze

  # Maps GEC file village names (uppercase) to canonical DB names
  VILLAGE_NAME_MAP = {
    # Hagåtña variants
    "hagatna" => "Hagåtña", "hagtna" => "Hagåtña", "hagtana" => "Hagåtña", "agana" => "Hagåtña",
    # Hågat variants
    "agat" => "Hågat", "hagat" => "Hågat",
    # Inalåhan variants
    "inarajan" => "Inalåhan", "inalahan" => "Inalåhan", "inajaran" => "Inalåhan", "inarjan" => "Inalåhan",
    # Malesso' variants
    "merizo" => "Malesso'", "malesso" => "Malesso'", "malesso'" => "Malesso'",
    # Talo'fo'fo' variants
    "talofofo" => "Talo'fo'fo'", "talo'fo'fo'" => "Talo'fo'fo'", "talo'fo'fo" => "Talo'fo'fo'", "talofo'fo" => "Talo'fo'fo'",
    # Humåtak variants
    "umatac" => "Humåtak", "humatak" => "Humåtak",
    # Sånta Rita-Sumai variants
    "santa rita" => "Sånta Rita-Sumai", "santa rita-sumai" => "Sånta Rita-Sumai",
    # Chalan Pago/Ordot variants
    "chalan pago" => "Chalan Pago/Ordot", "ordot" => "Chalan Pago/Ordot",
    "chalan pago/ordot" => "Chalan Pago/Ordot", "ordot/ chalan pago" => "Chalan Pago/Ordot",
    # Agana Heights variants
    "agana hts" => "Agana Heights", "agana heights" => "Agana Heights",
    # Mongmong/Toto/Maite variants
    "mongmong" => "Mongmong/Toto/Maite", "toto" => "Mongmong/Toto/Maite", "maite" => "Mongmong/Toto/Maite",
    "mongmong/toto/mait" => "Mongmong/Toto/Maite", "mtm" => "Mongmong/Toto/Maite",
    # Asan-Ma'ina variants
    "asan" => "Asan-Ma'ina", "maina" => "Asan-Ma'ina",
    # Direct matches (just lowercase versions)
    "dededo" => "Dededo", "tamuning" => "Tamuning", "yigo" => "Yigo",
    "barrigada" => "Barrigada", "yona" => "Yona", "sinajana" => "Sinajana",
    "mangilao" => "Mangilao", "piti" => "Piti",
    # Typos
    "barriagda" => "Barrigada", "barridaga" => "Barrigada",
    "sinjana" => "Sinajana", "tamunung" => "Tamuning",
    "deded" => "Dededo",
    "malojloj" => "Talo'fo'fo'",  # Malojloj is in Talo'fo'fo'
    # Tumon is part of Tamuning in GEC
    "tumon" => "Tamuning",
    # GMF (Guam Military Forces/base) - off-island or base residents → Unassigned village
    "gmf" => "Unassigned",
    "guam military forces" => "Unassigned",
    "military" => "Unassigned",
    "off-island" => "Unassigned",
    "off island" => "Unassigned",
    "overseas" => "Unassigned",
    "absentee" => "Unassigned"
  }.freeze

  OFFICIAL_VILLAGE_NAMES = [
    "Agana Heights",
    "Asan-Ma'ina",
    "Barrigada",
    "Chalan Pago/Ordot",
    "Dededo",
    "Hagåtña",
    "Hågat",
    "Humåtak",
    "Inalåhan",
    "Malesso'",
    "Mangilao",
    "Mongmong/Toto/Maite",
    "Piti",
    "Sinajana",
    "Sånta Rita-Sumai",
    "Talo'fo'fo'",
    "Tamuning",
    "Yigo",
    "Yona"
  ].freeze

  OFFICIAL_VILLAGE_LOOKUP = OFFICIAL_VILLAGE_NAMES.each_with_object({}) do |name, lookup|
    key = name.downcase
    lookup[key] = name
    lookup[I18n.transliterate(name).downcase] = name
  end.freeze

  # Village name used for voters with no village match (GMF, military, off-island)
  UNASSIGNED_VILLAGE_NAME = "Unassigned"
  PLACEHOLDER_VOTER_REGISTRATION_NUMBERS = %w[NEW].freeze
  VRN_LOOKUP_BATCH_SIZE = 5_000

  # Cache TTL for heartbeat and progress keys. Must exceed the longest
  # plausible import runtime (60K rows on a loaded DB can take >1 hour).
  # Keep this higher than any caller-level processing timeout so stale
  # artifacts do not disappear while an import is still being parsed.
  IMPORT_CACHE_TTL = 90.minutes


  Result = Struct.new(:success, :gec_import, :errors, :stats, keyword_init: true)

  class << self
    def normalized_name_component(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    def overlapping_name_component?(candidate, data)
      candidate_first = normalized_name_component(candidate.first_name)
      candidate_last = normalized_name_component(candidate.last_name)
      data_first = normalized_name_component(data[:first_name])
      data_last = normalized_name_component(data[:last_name])

      (candidate_first.present? && candidate_first == data_first) ||
        (candidate_last.present? && candidate_last == data_last)
    end

    def normalize_village_name(value, allow_unknown: true)
      raw = value.to_s.strip
      return nil if raw.blank?

      mapped = VILLAGE_NAME_MAP[raw.downcase]
      return mapped if mapped.present?

      official_match = OFFICIAL_VILLAGE_LOOKUP[raw.downcase] || OFFICIAL_VILLAGE_LOOKUP[I18n.transliterate(raw).downcase]
      return official_match if official_match.present?

      canonical = Village.where("LOWER(name) = ?", raw.downcase).pick(:name)
      return canonical if canonical.present?

      allow_unknown ? raw : nil
    end

    def normalize_voter_registration_number(value)
      raw = value.to_s.strip
      return nil if raw.blank?
      return nil if PLACEHOLDER_VOTER_REGISTRATION_NUMBERS.include?(raw.upcase)

      raw
    end

    def parse_birth_year(value)
      return nil if value.blank?

      case value
      when Integer
        value if value.between?(1900, Date.current.year)
      when Date, DateTime, Time
        year = value.year
        year if year.between?(1900, Date.current.year)
      when String
        year = value.strip.to_i
        year if year.between?(1900, Date.current.year)
      when Float
        year = value.to_i
        year if year.between?(1900, Date.current.year)
      end
    end

    def same_voter_name?(candidate, data)
      candidate.first_name.to_s.casecmp?(data[:first_name].to_s) &&
        candidate.last_name.to_s.casecmp?(data[:last_name].to_s)
    end

    def trusted_vrn_match?(candidate, data)
      return true if same_voter_name?(candidate, data)

      overlapping_name = overlapping_name_component?(candidate, data)
      same_village = candidate.village_name.to_s.strip.downcase == data[:village_name].to_s.strip.downcase
      return false unless same_village || overlapping_name

      if data[:dob].present? && !data[:dob_estimated]
        candidate.dob == data[:dob]
      elsif data[:birth_year].present?
        candidate.birth_year == data[:birth_year]
      else
        false
      end
    end
  end

  def initialize(
    file_path:,
    gec_list_date:,
    uploaded_by_user: nil,
    sheet_name: nil,
    import_type: "full_list",
    gec_import: nil,
    parsing_progress_percent: 10,
    importing_progress_start: 20,
    importing_progress_end: 85,
    re_vetting_progress_percent: 90
  )
    @file_path = file_path
    @gec_list_date = gec_list_date
    @uploaded_by_user = uploaded_by_user
    @sheet_name = sheet_name
    @import_type = import_type
    @errors = []
    @stats = { total: 0, new: 0, updated: 0, matched_unchanged: 0, ambiguous_dob: 0, skipped: 0, removed: 0, transferred: 0, re_vetted: 0, unassigned: 0 }
    @seen_voter_ids = Set.new
    @import_started_at = nil
    @gec_import = gec_import
    @row_error_details = []
    @change_rows_buffer = []
    @skipped_rows_buffer = []
    @source_identity_collision_keys = Set.new
    @source_identity_groups = {}
    @removal_detection_suppressed = false
    @vrn_lookup = {}
    # Preload village names to avoid N+1 queries during village detection loop
    @village_name_lookup = Village.pluck(:name).index_by { |n| n.downcase }
    @parsing_progress_percent = parsing_progress_percent
    @importing_progress_start = importing_progress_start
    @importing_progress_end = importing_progress_end
    @re_vetting_progress_percent = re_vetting_progress_percent
  end

  def call
    async_mode = @gec_import.present?
    gec_import = @gec_import || GecImport.create!(
      gec_list_date: @gec_list_date,
      filename: File.basename(@file_path),
      uploaded_by_user: @uploaded_by_user,
      import_type: @import_type,
      status: "processing"
    )
    @current_gec_import = gec_import

    begin
      update_progress!(gec_import, stage: "parsing", percent: @parsing_progress_percent) if async_mode
      Rails.logger.info(
        "GecImportService import=#{gec_import.id} opening spreadsheet file=#{File.basename(@file_path)} " \
        "sheet=#{@sheet_name || 0} import_type=#{@import_type}"
      )
      spreadsheet = Roo::Spreadsheet.open(@file_path)
      sheet = @sheet_name ? spreadsheet.sheet(@sheet_name) : spreadsheet.sheet(0)

      headers = normalize_headers(sheet.row(1))
      column_map = build_column_map(headers)

      has_split_names = column_map["first_name"] && column_map["last_name"]
      has_combined_name = column_map["combined_name"]
      unless has_split_names || has_combined_name
        raise "Missing required columns: need first_name+last_name OR name (combined). Found headers: #{headers.join(', ')}"
      end

      rows = (2..sheet.last_row).map { |i| sheet.row(i) }
      @stats[:total] = rows.size
      Rails.logger.info("GecImportService import=#{gec_import.id} parsed spreadsheet rows=#{rows.size}")
      @import_started_at = Time.current
      @source_identity_groups = build_source_identity_groups(rows, column_map)
      @source_identity_collision_keys = @source_identity_groups.each_with_object(Set.new) do |(key, group), collisions|
        collisions.add(key) if source_identity_requires_review?(group)
      end
      @vrn_lookup = build_voter_registration_lookup(rows, column_map)

      ActiveRecord::Base.transaction do
        rows.each_with_index do |row, idx|
          process_row(row, column_map, idx + 2) # +2 for 1-indexed header row

          if (idx % 500).zero?
            # NOTE: write_progress_cache is intentionally non-transactional.
            # Cache writes commit immediately regardless of the surrounding
            # DB transaction. If the transaction rolls back, the cached values
            # become stale. This is acceptable because the import status moves
            # to "failed" on rollback, and the controller only reads cached
            # progress for pending/processing imports.
            progress_span = [ @importing_progress_end - @importing_progress_start, 1 ].max
            progress = @importing_progress_start + ((idx.to_f / [ rows.size, 1 ].max) * progress_span).to_i
            write_progress_cache(gec_import.id, stage: "importing", percent: [ progress, @importing_progress_end ].min) if async_mode
          end
        end

        # For full list imports, detect purged voters (in DB but not in file)
        if @import_type == "full_list" && @seen_voter_ids.any? && removal_detection_allowed?
          detect_purged_voters(gec_import)
        elsif @import_type == "full_list" && @stats[:skipped] > 0
          @removal_detection_suppressed = true
        end

        flush_change_rows!
        flush_skipped_rows!
      end

      # Re-vet affected supporters (outside transaction for performance)
      update_progress!(gec_import, stage: "re_vetting", percent: @re_vetting_progress_percent) if async_mode
      Rails.logger.info("GecImportService import=#{gec_import.id} starting re-vetting")
      @stats[:re_vetted] = re_vet_affected_supporters(gec_import)

      completion_attrs = {
        total_records: @stats[:total],
        new_records: @stats[:new],
        updated_records: @stats[:updated],
        removed_records: @stats[:removed],
        transferred_records: @stats[:transferred],
        ambiguous_dob_count: @stats[:ambiguous_dob],
        re_vetted_count: @stats[:re_vetted],
        metadata: (gec_import.metadata || {}).merge({
          "stage" => async_mode ? "finalizing_artifact" : "completed",
          "progress_percent" => async_mode ? 95 : 100,
          "matched_unchanged" => @stats[:matched_unchanged],
          "skipped" => @stats[:skipped],
          "unassigned" => @stats[:unassigned],
          "review_required" => review_required?,
          "removal_detection_suppressed" => @removal_detection_suppressed,
          "errors" => @errors.first(MAX_STORED_ROW_ERRORS),
          "row_error_details" => @row_error_details
        })
      }
      completion_attrs[:status] = "completed" unless async_mode

      gec_import.update!(completion_attrs)

      Result.new(success: true, gec_import: gec_import, errors: @errors, stats: @stats)
    rescue => e
      gec_import.update!(
        status: "failed",
        metadata: (gec_import.metadata || {}).merge({ "stage" => "failed", "progress_percent" => 100, "error" => e.message })
      )
      Result.new(success: false, gec_import: gec_import, errors: [ e.message ], stats: @stats)
    end
  end

  # Preview first N rows without importing
  def preview(limit: 20)
    spreadsheet = Roo::Spreadsheet.open(@file_path)
    sheet = @sheet_name ? spreadsheet.sheet(@sheet_name) : spreadsheet.sheet(0)

    headers = normalize_headers(sheet.row(1))
    column_map = build_column_map(headers)
    sheets = spreadsheet.sheets

    rows = (2..[ sheet.last_row, limit + 1 ].min).map do |i|
      raw = sheet.row(i)
      parse_row(raw, column_map)
    end

    {
      headers: headers,
      column_map: column_map,
      sheets: sheets,
      row_count: sheet.last_row - 1,
      preview_rows: rows
    }
  end

  # Parse the entire file for viewer/search use-cases.
  def preview_all
    spreadsheet = Roo::Spreadsheet.open(@file_path)
    sheet = @sheet_name ? spreadsheet.sheet(@sheet_name) : spreadsheet.sheet(0)

    headers = normalize_headers(sheet.row(1))
    column_map = build_column_map(headers)
    sheets = spreadsheet.sheets
    row_count = [ (sheet.last_row || 1) - 1, 0 ].max
    rows = row_count.positive? ? (2..sheet.last_row).map { |i| parse_row(sheet.row(i), column_map) } : []

    {
      headers: headers,
      column_map: column_map,
      sheets: sheets,
      row_count: row_count,
      preview_rows: rows
    }
  end

  private

  def update_progress!(gec_import, stage:, percent:)
    write_progress_cache(gec_import.id, stage: stage, percent: percent)
    gec_import.update_columns(
      metadata: (gec_import.metadata || {}).merge({ "stage" => stage, "progress_percent" => percent, "updated_at" => Time.current.iso8601 }),
      updated_at: Time.current
    )
  end

  def write_progress_cache(import_id, stage:, percent:)
    now = Time.current.iso8601
    Rails.cache.write(
      "gec_import_progress:#{import_id}",
      { "stage" => stage, "progress_percent" => percent, "updated_at" => now },
      expires_in: IMPORT_CACHE_TTL
    )
    # Also refresh the heartbeat cache so stale-detector sees activity
    write_heartbeat_cache(import_id)
  rescue StandardError => e
    Rails.logger.warn("GEC progress cache write failed for import #{import_id}: #{e.class}: #{e.message}")
  end

  # Non-transactional heartbeat visible to any stale-processing detector.
  # DB updated_at is invisible during an open transaction, so monitors should
  # check this cache key first.
  #
  # TTL must exceed the longest plausible import. If the TTL expires before
  # the import finishes, the stale detector falls back to DB updated_at which
  # may be stale (set at "parsing" stage before the transaction opened).
  # Async callers should keep their retry windows shorter than the artifact
  # expiration window above.
  def write_heartbeat_cache(import_id)
    Rails.cache.write(
      "gec_import_heartbeat:#{import_id}",
      Time.current.iso8601,
      expires_in: IMPORT_CACHE_TTL
    )
  rescue StandardError => e
    Rails.logger.warn("GEC heartbeat cache write failed for import #{import_id}: #{e.class}: #{e.message}")
  end

  def normalize_village_name(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    mapped = VILLAGE_NAME_MAP[raw.downcase]
    return mapped if mapped.present?

    official_match = OFFICIAL_VILLAGE_LOOKUP[raw.downcase] || OFFICIAL_VILLAGE_LOOKUP[I18n.transliterate(raw).downcase]
    return official_match if official_match.present?

    @village_name_lookup[raw.downcase] || raw
  end

  def detect_known_village_name(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    mapped = VILLAGE_NAME_MAP[raw.downcase]
    return mapped if mapped.present?

    @village_name_lookup[raw.downcase]
  end

  def canonical_village_key(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    # Callers pass already-normalized or persisted village names, so avoid
    # re-running village normalization (which can fall through to DB lookups)
    # inside the hot import loop.
    raw.downcase
  end

  def normalize_voter_registration_number(value)
    self.class.normalize_voter_registration_number(value)
  end

  def build_voter_registration_lookup(rows, column_map)
    vrn_column = column_map["voter_registration_number"]
    return {} unless vrn_column

    vrns = rows.filter_map { |row| normalize_voter_registration_number(row[vrn_column]) }.uniq
    return {} if vrns.empty?

    vrns.each_slice(VRN_LOOKUP_BATCH_SIZE).each_with_object({}) do |slice, lookup|
      GecVoter.active.where(voter_registration_number: slice).each do |voter|
        (lookup[voter.voter_registration_number] ||= []) << voter
      end
    end
  end

  def build_source_identity_groups(rows, column_map)
    rows.each_with_object({}) do |row, groups|
      data = parse_row(row, column_map)
      key = source_identity_key(data)
      next unless key

      group = (groups[key] ||= {
        row_count: 0,
        vrns: Set.new,
        blank_vrn_count: 0
      })
      group[:row_count] += 1

      if data[:voter_registration_number].present?
        group[:vrns].add(data[:voter_registration_number])
      else
        group[:blank_vrn_count] += 1
      end
    end
  end

  def parse_booleanish(value)
    return false if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def source_identity_collision?(data)
    key = source_identity_key(data)
    key.present? && @source_identity_collision_keys.include?(key)
  end

  def source_identity_vrn_resolvable?(data)
    key = source_identity_key(data)
    return false unless key.present?

    group = @source_identity_groups[key]
    return false unless group

    group[:row_count] > 1 &&
      group[:blank_vrn_count].zero? &&
      group[:vrns].size == group[:row_count]
  end

  def source_identity_key(data)
    first_name = data[:first_name].to_s.strip.downcase
    last_name = data[:last_name].to_s.strip.downcase
    return nil if first_name.blank? || last_name.blank?

    birth_marker =
      if data[:dob].present? && !data[:dob_estimated]
        "dob:#{data[:dob].iso8601}"
      elsif data[:birth_year].present?
        "year:#{data[:birth_year]}"
      end
    return nil if birth_marker.blank?

    [ first_name, last_name, birth_marker ].join("|")
  end

  def source_identity_requires_review?(group)
    return false if group[:row_count] <= 1

    !(group[:blank_vrn_count].zero? && group[:vrns].size == group[:row_count])
  end

  def review_required?
    @stats[:skipped] > 0
  end

  def removal_detection_allowed?
    return true unless @import_type == "full_list"
    return true if @stats[:skipped].zero?

    @removal_detection_suppressed = true
    false
  end

  def resolve_unique_candidate(scope, row:, row_number:, data:, ambiguity_message:)
    candidates = scope.limit(2).to_a
    return candidates.first if candidates.one?
    return nil if candidates.empty?

    remember_row_error!(
      row_number: row_number,
      message: ambiguity_message,
      row: row,
      data: data
    )
    @stats[:skipped] += 1
    :ambiguous
  end

  def remember_row_error!(row_number:, message:, row:, data:)
    @errors << "Row #{row_number}: #{message}"

    now = Time.current
    @skipped_rows_buffer << {
      gec_import_id: @current_gec_import.id,
      row_number: row_number,
      message: message,
      source_name: data[:source_name],
      voter_registration_number: data[:voter_registration_number],
      first_name: data[:first_name],
      middle_name: data[:middle_name],
      last_name: data[:last_name],
      village_name: data[:village_name],
      birth_year: data[:birth_year],
      dob: data[:dob],
      raw_values: Array(row).map { |value| value.to_s.strip }.reject(&:blank?).first(10),
      created_at: now,
      updated_at: now
    } if @current_gec_import

    flush_skipped_rows! if @skipped_rows_buffer.length >= 500
    return if @row_error_details.length >= MAX_STORED_ROW_ERRORS

    @row_error_details << {
      "row_number" => row_number,
      "message" => message,
      "source_name" => data[:source_name],
      "voter_registration_number" => data[:voter_registration_number],
      "first_name" => data[:first_name],
      "middle_name" => data[:middle_name],
      "last_name" => data[:last_name],
      "village_name" => data[:village_name],
      "birth_year" => data[:birth_year],
      "raw_values" => Array(row).map { |value| value.to_s.strip }.reject(&:blank?).first(10)
    }
  end

  def log_change_row!(change_type:, current_values:, row_number: nil, details: {}, auto_flush: true)
    return unless @current_gec_import

    @change_rows_buffer << {
      gec_import_id: @current_gec_import.id,
      change_type: change_type,
      row_number: row_number,
      first_name: current_values[:first_name],
      middle_name: current_values[:middle_name],
      last_name: current_values[:last_name],
      voter_registration_number: current_values[:voter_registration_number],
      village_name: current_values[:village_name],
      previous_village_name: current_values[:previous_village_name],
      birth_year: current_values[:birth_year],
      dob: current_values[:dob],
      details: details.compact,
      created_at: Time.current,
      updated_at: Time.current
    }

    flush_change_rows! if auto_flush && @change_rows_buffer.length >= 500
  end

  def flush_change_rows!
    return if @change_rows_buffer.empty?

    GecImportChange.insert_all!(@change_rows_buffer)
    @change_rows_buffer.clear
  end

  def flush_skipped_rows!
    return if @skipped_rows_buffer.empty?

    GecImportSkippedRow.insert_all!(@skipped_rows_buffer)
    @skipped_rows_buffer.clear
  end

  def build_changed_fields(before_values, after_values)
    changed = {}
    after_values.each do |field, after_value|
      before_value = before_values[field]
      next if before_value == after_value

      changed[field.to_s] = {
        before: before_value,
        after: after_value
      }
    end
    changed
  end

  def normalize_headers(row)
    row.map { |h| h.to_s.strip.downcase.gsub(/\s+/, "_") }
  end

  def build_column_map(headers)
    map = {}
    COLUMN_ALIASES.each do |canonical, aliases|
      idx = headers.index { |h| aliases.include?(h) }
      map[canonical] = idx if idx
    end
    map
  end

  def parse_row(row, column_map)
    first_name = nil
    middle_name = nil
    last_name = nil

    if column_map["combined_name"]
      combined = row[column_map["combined_name"]]&.to_s&.strip
      if combined.present?
        parts = NameParser.split_gec_name(combined)
        first_name = parts[:first_name]
        middle_name = parts[:middle_name]
        last_name = parts[:last_name]
      end
    else
      first_name = row[column_map["first_name"]]&.to_s&.strip
      middle_name = row[column_map["middle_name"]]&.to_s&.strip.presence if column_map["middle_name"]
      last_name = row[column_map["last_name"]]&.to_s&.strip
    end

    # GEC file: village is in column after address (no header label)
    # Detect by checking column_map for combined_name pattern (GEC official format)
    village_name = nil
    if column_map["village"]
      village_name = normalize_village_name(row[column_map["village"]])
    elsif column_map["combined_name"] && column_map["dob"]
      # GEC format: village is typically at the column after address (index 4 for GEC Q1-GE6)
      # Try to detect by finding a known Guam village name in surrounding columns
      candidate_indices = (4..[ row.size - 1, 8 ].min).to_a + [ 3 ]
      candidate_indices.each do |ci|
        val = row[ci]&.to_s&.strip
        next unless val.present?
        normalized_village = detect_known_village_name(val)
        if normalized_village.present?
          village_name = normalized_village
          break
        end
      end
    end

    vrn = if column_map["voter_registration_number"]
      normalize_voter_registration_number(row[column_map["voter_registration_number"]])
    end

    precinct_number = if column_map["precinct_number"]
      row[column_map["precinct_number"]]&.to_s&.strip&.upcase.presence
    end

    address = nil
    if column_map["address"]
      address = row[column_map["address"]]&.to_s&.strip.presence
    elsif column_map["combined_name"]
      address = infer_combined_name_address(row, column_map)
    end

    dob = nil
    dob_ambiguous = false
    birth_year = nil

    if column_map["dob"]
      dob, dob_ambiguous = parse_dob(row[column_map["dob"]])
      birth_year = dob&.year
    end

    # Explicit birth_year column (new GEC format — year only)
    if column_map["birth_year"]
      parsed_year = parse_birth_year(row[column_map["birth_year"]])
      if parsed_year.present?
        # If both dob and birth_year present but years conflict, trust birth_year
        # and clear dob to avoid dob.year != birth_year inconsistency
        if dob.present? && dob.year != parsed_year
          dob = nil
          dob_ambiguous = false
        end
        birth_year = parsed_year
      end
      # If no full dob column at all, ensure dob stays nil
      dob = nil if column_map["dob"].blank?
    end

    dob_estimated = parse_booleanish(row[column_map["dob_estimated"]]) if column_map["dob_estimated"]
    if dob_estimated && birth_year.present?
      dob = nil
      dob_ambiguous = false
    end

    {
      first_name: first_name,
      middle_name: middle_name,
      last_name: last_name,
      dob: dob,
      dob_estimated: dob_estimated,
      dob_ambiguous: dob_ambiguous,
      birth_year: birth_year,
      village_name: village_name,
      address: address,
      precinct_number: precinct_number,
      voter_registration_number: vrn,
      source_name: column_map["combined_name"] ? row[column_map["combined_name"]]&.to_s&.strip : nil
    }
  end

  def infer_combined_name_address(row, column_map)
    combined_name_index = column_map["combined_name"]
    return nil if combined_name_index.nil?

    candidate_indices = ((combined_name_index + 1)..[ row.size - 1, 8 ].min).to_a
    return nil if candidate_indices.empty?

    detected_village_index = candidate_indices.find do |index|
      detect_known_village_name(row[index]).present?
    end

    address_indices = detected_village_index ? candidate_indices.select { |index| index < detected_village_index } : candidate_indices

    address_indices.each do |index|
      raw_value = row[index]&.to_s&.strip
      next if raw_value.blank?
      next if detect_known_village_name(raw_value).present?
      next if %w[GU GUAM].include?(raw_value.upcase)
      next if raw_value.match?(/\A\d+[A-Z]?\z/)

      parsed_dob, = parse_dob(raw_value)
      next if parsed_dob.present? || parse_birth_year(raw_value).present?

      return raw_value
    end

    nil
  end

  def process_row(row, column_map, row_number)
    data = parse_row(row, column_map)

    if data[:first_name].blank? || data[:last_name].blank?
      remember_row_error!(
        row_number: row_number,
        message: "missing first_name or last_name",
        row: row,
        data: data
      )
      @stats[:skipped] += 1
      return
    end

    if data[:source_name].present? && !data[:source_name].include?(",")
      remember_row_error!(
        row_number: row_number,
        message: "malformed source name: could not safely parse the voter name from this row",
        row: row,
        data: data
      )
      @stats[:skipped] += 1
      return
    end

    if data[:village_name].blank?
      # Route to "Unassigned" village instead of skipping
      # This captures GMF/military/off-island voters who have no standard village
      data[:village_name] = UNASSIGNED_VILLAGE_NAME
      @stats[:unassigned] += 1
    end

    collision_blocking = source_identity_collision?(data)
    collision_vrn_resolvable = source_identity_vrn_resolvable?(data)

    @stats[:ambiguous_dob] += 1 if data[:dob_ambiguous]

    # Find existing record: try name+village+(DOB or birth_year) first, then name+(DOB or birth_year) for transfers
    fn_lower = data[:first_name].downcase
    ln_lower = data[:last_name].downcase
    vn_lower = canonical_village_key(data[:village_name]) || data[:village_name].downcase

    record = nil
    trusted_voter_registration_number = data[:voter_registration_number]

    if data[:voter_registration_number].present?
      vrn_matches = @vrn_lookup.fetch(data[:voter_registration_number], [])

      if vrn_matches.size == 1
        candidate = vrn_matches.first
        if trusted_vrn_match?(candidate, data)
          record = candidate
        else
          trusted_voter_registration_number = nil
        end
      elsif vrn_matches.size > 1
        trusted_voter_registration_number = nil
      end
    end

    if collision_blocking && record.nil?
      remember_row_error!(
        row_number: row_number,
        message: "ambiguous source identity: multiple rows in this file collapse to the same simplified name and birth data",
        row: row,
        data: data
      )
      @stats[:skipped] += 1
      return
    end

    # First: exact match on name + village (+ DOB or birth_year if available)
    if record.nil? && !collision_vrn_resolvable
      scope = GecVoter.active.where("LOWER(first_name) = ? AND LOWER(last_name) = ? AND LOWER(village_name) = ?", fn_lower, ln_lower, vn_lower)
      if data[:dob].present? && !data[:dob_estimated]
        scope = scope.where(dob: data[:dob])
      elsif data[:birth_year].present?
        scope = scope.where(birth_year: data[:birth_year])
      end
      record = resolve_unique_candidate(
        scope,
        row: row,
        row_number: row_number,
        data: data,
        ambiguity_message: "ambiguous exact match: multiple active voters share the same name, village, and birth data"
      )
      return if record == :ambiguous
    end

    # Second: name + (DOB or birth_year) only (detects village transfer)
    if record.nil? && !collision_vrn_resolvable
      if data[:dob].present? && !data[:dob_estimated]
        record = resolve_unique_candidate(
          GecVoter.active.where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn_lower, ln_lower).where(dob: data[:dob]),
          row: row,
          row_number: row_number,
          data: data,
          ambiguity_message: "ambiguous transfer match: multiple active voters share the same name and date of birth"
        )
        return if record == :ambiguous
      elsif data[:birth_year].present?
        candidates = GecVoter.active.where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn_lower, ln_lower)
          .where(birth_year: data[:birth_year])

        # Birth-year-only matching can have legitimate duplicates across villages.
        # Only auto-transfer when there's exactly one active candidate.
        candidate_records = candidates.limit(2).to_a
        if candidate_records.one?
          record = candidate_records.first
        elsif candidate_records.many?
          remember_row_error!(
            row_number: row_number,
            message: "ambiguous transfer match: multiple active voters share the same name and birth year",
            row: row,
            data: data
          )
          @stats[:skipped] += 1
          return
        end
      end
    end

    if record
      if @seen_voter_ids.include?(record.id)
        remember_row_error!(
          row_number: row_number,
          message: "ambiguous repeated match: this row maps to a voter already matched earlier in the import",
          row: row,
          data: data
        )
        @stats[:skipped] += 1
        return
      end

      # Detect village transfer
      old_village = canonical_village_key(record.village_name)
      new_village = canonical_village_key(data[:village_name])
      village_changed = old_village.present? && new_village.present? && old_village != new_village
      previous_values = {
        first_name: record.first_name,
        middle_name: record.middle_name,
        last_name: record.last_name,
        address: record.address,
        precinct_number: record.precinct_number,
        village_name: record.village_name,
        voter_registration_number: record.voter_registration_number,
        dob: record.dob,
        birth_year: record.birth_year
      }

      attrs = {
        first_name: data[:first_name],
        middle_name: data[:middle_name],
        last_name: data[:last_name],
        gec_list_date: @gec_list_date,
        imported_at: @import_started_at,
        status: "active",
        removed_at: nil,
        removal_detected_by_import_id: nil,
        voter_registration_number: trusted_voter_registration_number || record.voter_registration_number,
        address: data[:address],
        precinct_number: data[:precinct_number],
        dob: data[:dob_estimated] ? record.dob : (data[:dob] || record.dob),
        dob_ambiguous: data[:dob_ambiguous].nil? ? record.dob_ambiguous : data[:dob_ambiguous],
        birth_year: data[:birth_year] || record.birth_year
      }

      if village_changed
        attrs[:previous_village_name] = record.village_name
        attrs[:village_name] = data[:village_name]
        attrs[:village_id] = nil # Will be re-resolved by before_validation
        @stats[:transferred] += 1
      end

      # Determine if any meaningful field actually changed.
      # NOTE: imported_at and gec_list_date are excluded by design — they are
      # bookkeeping timestamps that change on every import and would inflate
      # the :updated counter if included. They are still written via attrs
      # so the record reflects the latest import metadata.
      #
      # Also exclude dob_ambiguous-only flips from the public "updated" bucket.
      # Those are parser confidence changes, not voter-record changes.
      actually_changed = record.first_name != attrs[:first_name] ||
        record.middle_name != attrs[:middle_name] ||
        record.last_name != attrs[:last_name] ||
        record.address != attrs[:address] ||
        record.precinct_number != attrs[:precinct_number] ||
        village_changed ||
        record.status != attrs[:status] ||
        record.voter_registration_number != attrs[:voter_registration_number] ||
        record.dob != attrs[:dob] ||
        record.birth_year != attrs[:birth_year]

      record.update!(**attrs)
      @seen_voter_ids.add(record.id)
      if actually_changed
        change_type = village_changed ? "transferred" : "updated"
        log_change_row!(
          change_type: change_type,
          row_number: row_number,
          current_values: {
            first_name: record.first_name,
            middle_name: record.middle_name,
            last_name: record.last_name,
            address: record.address,
            precinct_number: record.precinct_number,
            village_name: record.village_name,
            previous_village_name: previous_values[:village_name],
            voter_registration_number: record.voter_registration_number,
            birth_year: record.birth_year,
            dob: record.dob
          },
          details: {
            changed_fields: build_changed_fields(previous_values, {
              first_name: record.first_name,
              middle_name: record.middle_name,
              last_name: record.last_name,
              address: record.address,
              precinct_number: record.precinct_number,
              village_name: record.village_name,
              voter_registration_number: record.voter_registration_number,
              dob: record.dob,
              birth_year: record.birth_year
            }),
            source_name: data[:source_name]
          }
        )
        @stats[:updated] += 1 if change_type == "updated"
      else
        @stats[:matched_unchanged] += 1
      end
    else
      voter = GecVoter.create!(
        first_name: data[:first_name],
        middle_name: data[:middle_name],
        last_name: data[:last_name],
        address: data[:address],
        precinct_number: data[:precinct_number],
        dob: data[:dob_estimated] ? nil : data[:dob],
        dob_ambiguous: data[:dob_ambiguous],
        birth_year: data[:birth_year],
        village_name: data[:village_name],
        voter_registration_number: trusted_voter_registration_number,
        gec_list_date: @gec_list_date,
        imported_at: @import_started_at,
        status: "active"
      )
      @seen_voter_ids.add(voter.id)
      log_change_row!(
        change_type: "new",
        row_number: row_number,
        current_values: {
          first_name: voter.first_name,
          middle_name: voter.middle_name,
          last_name: voter.last_name,
          village_name: voter.village_name,
          voter_registration_number: voter.voter_registration_number,
          birth_year: voter.birth_year,
          dob: voter.dob
        },
        details: {
          source_name: data[:source_name]
        }
      )
      @stats[:new] += 1
    end
  end

  # Mark voters as removed if they were active but not seen in this specific full-list import run.
  # Uses import_started_at (run marker), so same-date reruns are handled correctly.
  def detect_purged_voters(gec_import)
    purged = GecVoter.active.where("imported_at IS NULL OR imported_at < ?", @import_started_at)
    count = purged.count

    purged.find_each do |gv|
      log_change_row!(
        change_type: "removed",
        current_values: {
          first_name: gv.first_name,
          middle_name: gv.middle_name,
          last_name: gv.last_name,
          village_name: gv.village_name,
          previous_village_name: gv.previous_village_name,
          voter_registration_number: gv.voter_registration_number,
          birth_year: gv.birth_year,
          dob: gv.dob
        },
        details: {
          reason: "missing_from_full_list"
        },
        auto_flush: false
      )
    end

    purged.update_all(
      status: "removed",
      removed_at: Time.current,
      removal_detected_by_import_id: gec_import.id
    )

    @stats[:removed] = count
  end

  # Re-vet all active supporters against the latest GEC data after each import.
  # This keeps supporter voter-check statuses current when people appear, move,
  # disappear, or become newly resolvable in a newer monthly list.
  def re_vet_affected_supporters(_gec_import)
    count = 0
    supporters = Supporter.contacts.includes(:village)

    supporters.find_each do |supporter|
      before = supporter.attributes.slice("verification_status", "registered_voter", "referred_from_village_id", "verified_at")
      GecVettingService.new(supporter, gec_data_loaded: true).call
      supporter.reload
      after = supporter.attributes.slice("verification_status", "registered_voter", "referred_from_village_id", "verified_at")
      count += 1 if before != after
    end

    count
  end

  # Parse a year-only birth year value (new GEC format).
  # Accepts: integer (1985), string ("1985"), or a Date/DateTime (extracts year).
  def parse_birth_year(value)
    self.class.parse_birth_year(value)
  end

  def same_voter_name?(candidate, data)
    self.class.same_voter_name?(candidate, data)
  end

  def trusted_vrn_match?(candidate, data)
    self.class.trusted_vrn_match?(candidate, data)
  end

  # Parse DOB with month/day swap detection.
  # When PDF→Excel conversion happens, month and day sometimes swap.
  # If both values are ≤ 12, we can't tell which is correct → flag as ambiguous.
  def parse_dob(value)
    return [ nil, false ] if value.blank?

    date = case value
    when Date, DateTime, Time
      value.to_date
    when String
      begin
        Date.parse(value)
      rescue Date::Error
        # Try common formats
        begin
          Date.strptime(value, "%m/%d/%Y")
        rescue Date::Error
          begin
            Date.strptime(value, "%d/%m/%Y")
          rescue Date::Error
            nil
          end
        end
      end
    when Numeric
      # Excel serial date number
      begin
        # Excel epoch is 1899-12-30
        (Date.new(1899, 12, 30) + value.to_i).to_date
      rescue
        nil
      end
    end

    return [ nil, false ] if date.nil?

    # DOB ambiguity check: if both month and day ≤ 12, we can't be sure
    # the PDF→Excel conversion didn't swap them
    ambiguous = date.day <= 12 && date.month != date.day

    [ date, ambiguous ]
  end
end
