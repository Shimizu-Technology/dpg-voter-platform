# frozen_string_literal: true

# Automatically vets a supporter against the GEC voter registration list.
# Called after supporter creation to set verification_status and registered_voter.
#
# Results:
#   - :auto_verified  — exact match found, supporter auto-verified
#   - :flagged        — fuzzy or ambiguous match, needs manual review
#   - :referral       — matched but in a different village
#   - :unregistered   — no match found in GEC list
#   - :skipped        — no GEC data loaded yet
class GecVettingService
  Result = Struct.new(:status, :matches, :gec_voter, :details, :match_count, keyword_init: true)

  def initialize(supporter, gec_data_loaded: nil)
    @supporter = supporter
    @gec_data_loaded = gec_data_loaded
  end

  def call
    gec_data_loaded = @gec_data_loaded.nil? ? GecVoter.active.exists? : @gec_data_loaded
    return Result.new(status: :skipped, matches: [], match_count: 0, details: "No GEC voter data loaded") unless gec_data_loaded

    # birth_year: derive from dob if available (supporters store full DOB if provided at signup)
    supporter_birth_year = @supporter.respond_to?(:birth_year) ? @supporter.birth_year : nil
    supporter_birth_year ||= @supporter.dob&.year

    matches = GecVoter.find_matches(
      first_name: @supporter.first_name,
      last_name: @supporter.last_name,
      dob: @supporter.dob,
      birth_year: supporter_birth_year,
      village_name: @supporter.village&.name
    )

    if matches.empty?
      apply_unregistered!
      return Result.new(status: :unregistered, matches: [], match_count: 0, details: "No match found in voter list")
    end

    best = matches.first
    count = best[:match_count] || matches.size

    case best[:confidence]
    when :exact
      apply_auto_verified!(best[:gec_voter])
      Result.new(
        status: :auto_verified, matches: matches, gec_voter: best[:gec_voter], match_count: count,
        details: "Exact match: #{best[:gec_voter].first_name} #{best[:gec_voter].last_name}, #{best[:gec_voter].village_name}"
      )
    when :high
      if best[:match_type] == :different_village
        apply_referral!(best[:gec_voter])
        Result.new(
          status: :referral, matches: matches, gec_voter: best[:gec_voter], match_count: count,
          details: "Registered in #{best[:gec_voter].village_name}, not #{@supporter.village&.name}"
        )
      elsif count > 1
        apply_flagged!(
          best[:gec_voter],
          reason: "multiple_matches",
          confidence: best[:confidence].to_s,
          match_type: best[:match_type].to_s,
          match_count: count
        )
        Result.new(
          status: :flagged, matches: matches, gec_voter: best[:gec_voter], match_count: count,
          details: "#{count} high-confidence candidates found — manual review required"
        )
      else
        apply_auto_verified!(best[:gec_voter])
        Result.new(
          status: :auto_verified, matches: matches, gec_voter: best[:gec_voter], match_count: count,
          details: "High confidence match: #{best[:gec_voter].first_name} #{best[:gec_voter].last_name}"
        )
      end
    when :medium
      reason = if best[:match_type] == :fuzzy_name_year
        "fuzzy_name_match"
      elsif count > 1
        "multiple_matches"
      else
        "needs_manual_review"
      end
      apply_flagged!(
        best[:gec_voter],
        reason: reason,
        confidence: best[:confidence].to_s,
        match_type: best[:match_type].to_s,
        match_count: count
      )
      detail = if best[:match_type] == :fuzzy_name_year
        "Fuzzy name match — needs manual review"
      elsif count > 1
        "#{count} possible matches with same birth year — needs manual review"
      else
        "Possible GEC match with same birth year — needs manual review"
      end
      Result.new(
        status: :flagged, matches: matches, gec_voter: best[:gec_voter], match_count: count,
        details: detail
      )
    when :low
      apply_flagged!(
        best[:gec_voter],
        reason: "low_confidence_match",
        confidence: best[:confidence].to_s,
        match_type: best[:match_type].to_s,
        match_count: count
      )
      Result.new(
        status: :flagged, matches: matches, gec_voter: best[:gec_voter], match_count: count,
        details: "Low confidence match (name + village only, no birth year)"
      )
    else
      apply_flagged!(
        best[:gec_voter],
        reason: "needs_manual_review",
        confidence: best[:confidence].to_s,
        match_type: best[:match_type].to_s,
        match_count: count
      )
      Result.new(
        status: :flagged, matches: matches, gec_voter: best[:gec_voter], match_count: count,
        details: "Unknown confidence level"
      )
    end
  end

  private

  def apply_auto_verified!(gec_voter)
    updates = {
      gec_voter_id: gec_voter.id,
      precinct_id: gec_voter.precinct_id,
      verification_status: "verified",
      registered_voter: true,
      referred_from_village_id: nil,
      verification_reason: "matched_current_gec",
      turnout_status: gec_voter.turnout_status,
      turnout_note: gec_voter.turnout_note,
      turnout_source: gec_voter.turnout_source,
      turnout_updated_at: gec_voter.turnout_updated_at,
      turnout_updated_by_user_id: gec_voter.turnout_updated_by_user_id,
      verification_reason_metadata: verification_reason_metadata(
        gec_voter: gec_voter,
        confidence: "exact",
        match_type: "current_gec_match",
        match_count: 1
      )
    }
    updates[:verified_at] = Time.current if @supporter.verification_status != "verified" || @supporter.verified_at.blank?
    apply_updates!(updates)
  end

  def apply_flagged!(gec_voter, reason:, confidence:, match_type:, match_count:)
    apply_updates!(
      gec_voter_id: nil,
      verification_status: "flagged",
      registered_voter: true,
      referred_from_village_id: nil,
      verified_at: nil,
      verification_reason: reason,
      verification_reason_metadata: verification_reason_metadata(
        gec_voter: gec_voter,
        confidence: confidence,
        match_type: match_type,
        match_count: match_count
      )
    )
  end

  def apply_referral!(gec_voter)
    referred_village = Village.find_by("LOWER(name) = ?", gec_voter.village_name.downcase.strip)
    apply_updates!(
      gec_voter_id: nil,
      verification_status: "flagged",
      registered_voter: true,
      referred_from_village_id: referred_village&.id,
      verified_at: nil,
      verification_reason: "village_mismatch",
      verification_reason_metadata: verification_reason_metadata(
        gec_voter: gec_voter,
        confidence: "high",
        match_type: "different_village"
      )
    )
  end

  def apply_unregistered!
    apply_updates!(
      gec_voter_id: nil,
      verification_status: "unverified",
      registered_voter: false,
      referred_from_village_id: nil,
      verified_at: nil,
      verification_reason: "no_gec_match",
      verification_reason_metadata: {}
    )
  end

  def apply_updates!(attributes)
    updates = attributes.each_with_object({}) do |(key, value), changed|
      changed[key] = value if @supporter.public_send(key) != value
    end

    @supporter.update_columns(updates) if updates.present?
  end

  def verification_reason_metadata(gec_voter:, confidence:, match_type:, match_count: nil)
    {
      "gec_village_name" => gec_voter&.village_name,
      "confidence" => confidence,
      "match_type" => match_type,
      "match_count" => match_count
    }.compact
  end
end
