# frozen_string_literal: true

class SupporterVerificationReasonService
  def initialize(supporter, matches: nil, allow_match_lookup: false)
    @supporter = supporter
    @matches = matches
    @allow_match_lookup = allow_match_lookup
  end

  def payload
    reason = persisted_reason
    return reason if reason

    derived_reason
  end

  private

  attr_reader :supporter, :allow_match_lookup

  def persisted_reason
    reason_code = supporter.verification_reason.to_s.presence
    return nil unless reason_code

    build_payload(reason_code, metadata: normalized_metadata, derived: false)
  end

  def derived_reason
    if supporter.referred_from_village_id.present?
      return build_payload(
        "village_mismatch",
        metadata: {
          "gec_village_name" => supporter.referred_from_village&.name
        },
        derived: true
      )
    end

    if supporter.verification_status == "unverified" && supporter.registered_voter == false
      return build_payload("no_gec_match", metadata: {}, derived: true)
    end

    return nil unless supporter.verification_status == "flagged"

    best_match = matches.first
    return build_payload(derived_reason_code_for(best_match), metadata: derived_metadata_for(best_match), derived: true) if best_match

    build_payload("needs_manual_review", metadata: {}, derived: true)
  end

  def derived_reason_code_for(match)
    match_type = match[:match_type].to_s
    match_count = match[:match_count].to_i

    return "village_mismatch" if match_type == "different_village"
    return "fuzzy_name_match" if match_type == "fuzzy_name_year"
    return "low_confidence_match" if match_type == "name_village_only" || match[:confidence].to_s == "low"
    return "multiple_matches" if match_count > 1

    "needs_manual_review"
  end

  def derived_metadata_for(match)
    {
      "match_type" => match[:match_type].to_s.presence,
      "confidence" => match[:confidence].to_s.presence,
      "match_count" => match[:match_count].to_i.positive? ? match[:match_count].to_i : nil,
      "gec_village_name" => match[:gec_voter]&.village_name
    }.compact
  end

  def build_payload(reason_code, metadata:, derived:)
    {
      verification_reason: reason_code,
      verification_reason_label: label_for(reason_code),
      verification_reason_detail: detail_for(reason_code, metadata),
      verification_reason_metadata: metadata,
      verification_reason_derived: derived
    }
  end

  def label_for(reason_code)
    case reason_code
    when "matched_current_gec", "manual_staff_verified"
      "Matched to GEC"
    when "village_mismatch"
      "Village Referral"
    when "no_gec_match"
      "No GEC Match"
    when "multiple_matches"
      "Multiple Matches"
    when "fuzzy_name_match"
      "Fuzzy Name Match"
    when "low_confidence_match"
      "Low Confidence Match"
    when "manual_staff_flag"
      "Staff Flagged"
    when "needs_manual_review"
      "Needs Review"
    else
      "Flagged for review"
    end
  end

  def detail_for(reason_code, metadata)
    case reason_code
    when "matched_current_gec"
      "This supporter has a current GEC match and can be treated as matched to the voter list."
    when "manual_staff_verified"
      "This supporter was manually marked as matched to GEC by staff."
    when "village_mismatch"
      if supporter.village&.name.present? && metadata["gec_village_name"].present?
        "This supporter is currently assigned to #{supporter.village.name}, but the current GEC match is in #{metadata['gec_village_name']}."
      elsif metadata["gec_village_name"].present?
        "This supporter matched a current GEC voter in #{metadata['gec_village_name']}, so staff should review the village assignment."
      else
        "This supporter appears to be registered in a different village and should be reviewed by staff."
      end
    when "multiple_matches"
      count = metadata["match_count"].to_i
      if count > 1
        "This supporter was flagged because #{count} possible GEC matches were found and staff should confirm the correct voter."
      else
        "This supporter was flagged because multiple possible GEC matches were found and staff should confirm the correct voter."
      end
    when "fuzzy_name_match"
      "This supporter was flagged because the best GEC match was only a fuzzy name match and needs manual review."
    when "low_confidence_match"
      "This supporter was flagged because the best GEC match was low confidence and needs manual review."
    when "no_gec_match"
      "This supporter was not found in the current voter list."
    when "manual_staff_flag"
      "This supporter was flagged manually by staff for voter-check follow-up."
    when "needs_manual_review"
      "This supporter needs voter-check follow-up before staff should treat the match as confirmed."
    else
      "This supporter needs voter-check follow-up before staff should treat the match as confirmed."
    end
  end

  def normalized_metadata
    raw = supporter.verification_reason_metadata
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  end

  def matches
    @matches ||= if allow_match_lookup
      GecVoter.find_matches(
        first_name: supporter.first_name,
        last_name: supporter.last_name,
        dob: supporter.dob,
        birth_year: supporter.dob&.year,
        village_name: supporter.village&.name
      )
    else
      []
    end
  end
end
