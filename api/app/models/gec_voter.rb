# frozen_string_literal: true

class GecVoter < ApplicationRecord
  STATUSES = %w[active removed].freeze
  TURNOUT_STATUSES = %w[unknown not_yet_voted voted observed_elsewhere].freeze
  TURNOUT_SOURCES = %w[poll_watcher data_team admin_override].freeze

  belongs_to :village, optional: true
  belongs_to :precinct, optional: true
  belongs_to :removal_detected_by_import, class_name: "GecImport", optional: true
  belongs_to :turnout_updated_by_user, class_name: "User", optional: true
  has_many :supporters, dependent: :nullify

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :village_name, presence: true
  validates :gec_list_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :turnout_status, inclusion: { in: TURNOUT_STATUSES }
  validates :turnout_source, inclusion: { in: TURNOUT_SOURCES }, allow_blank: true

  before_validation :normalize_precinct_number
  before_validation :resolve_village
  before_validation :resolve_precinct

  scope :active, -> { where(status: "active") }
  scope :removed, -> { where(status: "removed") }
  scope :transferred, -> { where.not(previous_village_name: nil) }
  scope :for_list_date, ->(date) { where(gec_list_date: date) }
  scope :with_ambiguous_dob, -> { where(dob_ambiguous: true) }
  scope :recently_removed, -> { removed.where("removed_at > ?", 60.days.ago) }
  scope :not_yet_voted, -> { where(turnout_status: "not_yet_voted") }
  scope :observed_elsewhere, -> { where(turnout_status: "observed_elsewhere") }

  def self.election_day_list_date
    GecImport.active_election_day_import&.gec_list_date || active.maximum(:gec_list_date)
  end

  def self.election_day_active
    list_date = election_day_list_date
    scope = active
    list_date.present? ? scope.for_list_date(list_date) : scope
  end

  # Find potential matches for a supporter against the GEC voter list.
  # Returns array of hashes: { gec_voter:, confidence:, match_type:, match_count: }
  #
  # Confidence tiers (adapts to whether full DOB or birth_year_only is available):
  #   :exact  — name + full DOB + village → 1 match (legacy, backwards compat)
  #   :exact  — name + birth_year + village → exactly 1 match (new GEC format)
  #   :high   — name + birth_year + village → 2-3 matches (likely correct, note ambiguity)
  #   :high   — name + birth_year, different village → referral candidate
  #   :medium — name + birth_year + village → 4+ matches (too many, manual review)
  #   :medium — fuzzy name + birth_year/DOB
  #   :low    — name + village only (no birth info)
  def self.find_matches(first_name:, last_name:, dob: nil, birth_year: nil, village_name: nil)
    matches = []
    fn = first_name.to_s.downcase.strip
    ln = last_name.to_s.downcase.strip
    vn = village_name.to_s.downcase.strip

    # Derive birth_year from dob if not provided
    effective_birth_year = birth_year || dob&.year

    # --- Strategy 1: Exact name + full DOB + village (legacy/backwards compat) ---
    if dob.present? && village_name.present?
      exact = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where(dob: dob)
        .where("LOWER(village_name) = ?", vn)
        .to_a

      if exact.any?
        exact.each do |gv|
          matches << { gec_voter: gv, confidence: :exact, match_type: :exact_dob_village, match_count: exact.size }
        end
        return matches
      end

      # Exact name + full DOB, different village → referral
      diff_village = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where(dob: dob)
        .where.not("LOWER(village_name) = ?", vn)
        .to_a

      if diff_village.any?
        diff_village.each do |gv|
          matches << { gec_voter: gv, confidence: :high, match_type: :different_village, match_count: diff_village.size }
        end
        return matches
      end
    end

    # --- Strategy 2: Name + birth_year + village (primary path for new GEC format) ---
    if effective_birth_year.present? && village_name.present?
      name_year_village = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where(birth_year: effective_birth_year)
        .where("LOWER(village_name) = ?", vn)
        .to_a

      if name_year_village.any?
        count = name_year_village.size
        confidence = case count
        when 1     then :exact
        when 2, 3  then :high
        else            :medium
        end

        name_year_village.each do |gv|
          matches << { gec_voter: gv, confidence: confidence, match_type: :name_year_village, match_count: count }
        end
        return matches
      end

      # Name + birth_year, different village → referral candidate
      diff_village = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where(birth_year: effective_birth_year)
        .where.not("LOWER(village_name) = ?", vn)
        .to_a

      if diff_village.any?
        diff_village.each do |gv|
          matches << { gec_voter: gv, confidence: :high, match_type: :different_village, match_count: diff_village.size }
        end
        return matches
      end
    end

    # --- Strategy 3: Name + birth_year only (no village — only reached when village is blank) ---
    if effective_birth_year.present? && village_name.blank? && matches.empty?
      name_year = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where(birth_year: effective_birth_year)
        .to_a

      if name_year.any?
        name_year.each do |gv|
          matches << { gec_voter: gv, confidence: :medium, match_type: :name_year_only, match_count: name_year.size }
        end
        return matches
      end
    end

    # --- Strategy 4: Fuzzy name + birth_year ---
    if effective_birth_year.present? && matches.empty?
      fuzzy = active
        .where(birth_year: effective_birth_year)
        .where(
          "similarity(LOWER(first_name), ?) > 0.4 AND similarity(LOWER(last_name), ?) > 0.4",
          fn, ln
        )
        .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "similarity(LOWER(last_name), ?) DESC", ln ])))
        .limit(5)
        .to_a

      if fuzzy.any?
        fuzzy.each do |gv|
          matches << { gec_voter: gv, confidence: :medium, match_type: :fuzzy_name_year, match_count: fuzzy.size }
        end
        return matches
      end
    end

    # --- Strategy 5: Name + village only (no birth info — last resort) ---
    if village_name.present? && matches.empty?
      name_village = active
        .where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fn, ln)
        .where("LOWER(village_name) = ?", vn)
        .to_a

      name_village.each do |gv|
        matches << { gec_voter: gv, confidence: :low, match_type: :name_village_only, match_count: name_village.size }
      end
    end

    matches
  end

  def self.find_matches_for_supporters(supporters)
    inputs = supporters.filter_map { |supporter| build_match_input_for(supporter) }
    unresolved = inputs.index_by { |input| input[:supporter_id] }
    results = Hash.new { |hash, key| hash[key] = [] }

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.dob IS NOT NULL AND supporter_lookups.village_name_norm <> ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND gec_voters.dob = supporter_lookups.dob
        AND LOWER(gec_voters.village_name) = supporter_lookups.village_name_norm
      SQL
      confidence_for: ->(_count) { :exact },
      match_type: :exact_dob_village
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.dob IS NOT NULL AND supporter_lookups.village_name_norm <> ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND gec_voters.dob = supporter_lookups.dob
        AND LOWER(gec_voters.village_name) <> supporter_lookups.village_name_norm
      SQL
      confidence_for: ->(_count) { :high },
      match_type: :different_village
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.birth_year IS NOT NULL AND supporter_lookups.village_name_norm <> ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND gec_voters.birth_year = supporter_lookups.birth_year
        AND LOWER(gec_voters.village_name) = supporter_lookups.village_name_norm
      SQL
      confidence_for: lambda { |count|
        case count
        when 1 then :exact
        when 2, 3 then :high
        else :medium
        end
      },
      match_type: :name_year_village
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.birth_year IS NOT NULL AND supporter_lookups.village_name_norm <> ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND gec_voters.birth_year = supporter_lookups.birth_year
        AND LOWER(gec_voters.village_name) <> supporter_lookups.village_name_norm
      SQL
      confidence_for: ->(_count) { :high },
      match_type: :different_village
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.birth_year IS NOT NULL AND supporter_lookups.village_name_norm = ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND gec_voters.birth_year = supporter_lookups.birth_year
      SQL
      confidence_for: ->(_count) { :medium },
      match_type: :name_year_only
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: <<~SQL.squish,
        supporter_lookups.birth_year IS NOT NULL
        AND similarity(LOWER(gec_voters.first_name), supporter_lookups.first_name_norm) > 0.4
        AND similarity(LOWER(gec_voters.last_name), supporter_lookups.last_name_norm) > 0.4
      SQL
      join_sql: "gec_voters.birth_year = supporter_lookups.birth_year",
      confidence_for: ->(_count) { :medium },
      match_type: :fuzzy_name_year,
      order_sql: <<~SQL.squish,
        similarity(LOWER(gec_voters.last_name), supporter_lookups.last_name_norm) DESC,
        similarity(LOWER(gec_voters.first_name), supporter_lookups.first_name_norm) DESC
      SQL
      limit_per_supporter: 5
    )

    resolve_batch_matches!(results, unresolved,
      where_sql: "supporter_lookups.village_name_norm <> ''",
      join_sql: <<~SQL.squish,
        LOWER(gec_voters.first_name) = supporter_lookups.first_name_norm
        AND LOWER(gec_voters.last_name) = supporter_lookups.last_name_norm
        AND LOWER(gec_voters.village_name) = supporter_lookups.village_name_norm
      SQL
      confidence_for: ->(_count) { :low },
      match_type: :name_village_only
    )

    results
  end

  private

  def self.build_match_input_for(supporter)
    return nil unless supporter&.id

    {
      supporter_id: supporter.id,
      first_name_norm: supporter.first_name.to_s.downcase.strip,
      last_name_norm: supporter.last_name.to_s.downcase.strip,
      dob: supporter.dob,
      birth_year: supporter.dob&.year,
      village_name_norm: supporter.village&.name.to_s.downcase.strip
    }
  end

  def self.resolve_batch_matches!(results, unresolved, where_sql:, join_sql:, confidence_for:, match_type:, order_sql: nil, limit_per_supporter: nil)
    return if unresolved.empty?

    matches_by_supporter = batch_query_matches(
      unresolved.values,
      where_sql: where_sql,
      join_sql: join_sql,
      order_sql: order_sql,
      limit_per_supporter: limit_per_supporter
    )

    matches_by_supporter.each do |supporter_id, rows|
      count = rows.first.read_attribute("match_count").to_i
      results[supporter_id] = rows.map do |row|
        {
          gec_voter: row,
          confidence: confidence_for.call(count),
          match_type: match_type,
          match_count: count
        }
      end
      unresolved.delete(supporter_id)
    end
  end

  def self.batch_query_matches(inputs, where_sql:, join_sql:, order_sql: nil, limit_per_supporter: nil)
    return {} if inputs.empty?
    if limit_per_supporter && order_sql.blank?
      raise ArgumentError, "order_sql is required when limit_per_supporter is set"
    end

    outer_order_sql = if limit_per_supporter
      "supporter_lookup_id, supporter_match_rank"
    else
      "supporter_lookup_id"
    end

    rows = find_by_sql(<<~SQL)
      WITH supporter_lookups AS (
        SELECT
          raw.supporter_id::bigint AS supporter_id,
          raw.first_name_norm::text AS first_name_norm,
          raw.last_name_norm::text AS last_name_norm,
          raw.dob::date AS dob,
          raw.birth_year::integer AS birth_year,
          raw.village_name_norm::text AS village_name_norm
        FROM (
          VALUES #{match_lookup_values_sql(inputs)}
        ) AS raw(
          supporter_id,
          first_name_norm,
          last_name_norm,
          dob,
          birth_year,
          village_name_norm
        )
      ),
      matched_rows AS (
        SELECT
          gec_voters.*,
          supporter_lookups.supporter_id AS supporter_lookup_id,
          COUNT(*) OVER (PARTITION BY supporter_lookups.supporter_id) AS match_count
          #{limit_per_supporter ? ", ROW_NUMBER() OVER (PARTITION BY supporter_lookups.supporter_id ORDER BY #{order_sql}) AS supporter_match_rank" : ""}
        FROM gec_voters
        INNER JOIN supporter_lookups
          ON #{join_sql}
        WHERE gec_voters.status = 'active'
          AND #{where_sql}
      )
      SELECT *
      FROM matched_rows
      #{limit_per_supporter ? "WHERE supporter_match_rank <= #{limit_per_supporter}" : ""}
      ORDER BY #{outer_order_sql}
    SQL

    rows.group_by { |row| row.read_attribute("supporter_lookup_id").to_i }
  end

  def self.match_lookup_values_sql(inputs)
    connection = ActiveRecord::Base.connection

    inputs.map do |input|
      [
        connection.quote(input[:supporter_id]),
        connection.quote(input[:first_name_norm]),
        connection.quote(input[:last_name_norm]),
        connection.quote(input[:dob]),
        connection.quote(input[:birth_year]),
        connection.quote(input[:village_name_norm])
      ].yield_self { |values| "(#{values.join(', ')})" }
    end.join(", ")
  end
  private_class_method :build_match_input_for, :resolve_batch_matches!, :batch_query_matches, :match_lookup_values_sql

  def normalize_precinct_number
    self.precinct_number = precinct_number.to_s.strip.upcase.presence
  end

  def resolve_village
    return if village_id.present? || village_name.blank?

    canonical_name = GecImportService.normalize_village_name(village_name, allow_unknown: false) || GecImportService::UNASSIGNED_VILLAGE_NAME
    self.village_name = canonical_name

    found = Village.find_by("LOWER(name) = ?", canonical_name.downcase)
    self.village_id = found&.id
  end

  def resolve_precinct
    if village_id.blank? || precinct_number.blank?
      self.precinct_id = nil
      return
    end

    self.precinct_id = Precinct.find_by(village_id: village_id, number: precinct_number)&.id
  end
end
