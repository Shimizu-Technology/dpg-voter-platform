# frozen_string_literal: true

class GecImportSkippedRowResolutionService
  PREVIEW_STATUSES = %w[invalid conflict ambiguous ready_to_create ready_to_update already_resolved].freeze

  Result = Struct.new(
    :success,
    :status,
    :errors,
    :message,
    :corrected_values,
    :suggested_action,
    :target_voter,
    :candidate_matches,
    :skipped_row,
    keyword_init: true
  )

  def initialize(skipped_row:, actor_user:, attributes: {}, selected_gec_voter_id: nil)
    @skipped_row = skipped_row
    @actor_user = actor_user
    @attributes = attributes || {}
    @selected_gec_voter_id = selected_gec_voter_id.presence
  end

  def preview
    return already_resolved_result unless @skipped_row.resolution_status == "pending"

    corrected = normalize_corrected_values
    errors = validate_corrected_values(corrected)
    return build_result(success: false, status: "invalid", errors: errors, corrected_values: corrected) if errors.any?

    vrn_candidate, vrn_errors = resolve_vrn_candidate(corrected)
    return build_result(success: false, status: "conflict", errors: vrn_errors, corrected_values: corrected) if vrn_errors.any?

    matches = build_candidate_matches(corrected, preferred_voter: vrn_candidate)

    if @selected_gec_voter_id.present?
      selected = matches.find { |entry| entry[:gec_voter].id == @selected_gec_voter_id.to_i }
      return build_result(success: false, status: "ambiguous", errors: [ "Select one of the suggested voters before applying this fix." ], corrected_values: corrected, candidate_matches: matches) unless selected

      return build_result(
        success: true,
        status: "ready_to_update",
        corrected_values: corrected,
        suggested_action: "update",
        target_voter: selected[:gec_voter],
        candidate_matches: matches
      )
    end

    if vrn_candidate
      return build_result(
        success: true,
        status: "ready_to_update",
        corrected_values: corrected,
        suggested_action: "update",
        target_voter: vrn_candidate,
        candidate_matches: matches
      )
    end

    if matches.empty?
      return build_result(
        success: true,
        status: "ready_to_create",
        corrected_values: corrected,
        suggested_action: "create",
        candidate_matches: []
      )
    end

    if matches.one? && safe_single_match?(matches.first)
      return build_result(
        success: true,
        status: "ready_to_update",
        corrected_values: corrected,
        suggested_action: "update",
        target_voter: matches.first[:gec_voter],
        candidate_matches: matches
      )
    end

    build_result(
      success: false,
      status: "ambiguous",
      errors: [ "Multiple possible voters match this correction. Choose the correct voter before applying." ],
      corrected_values: corrected,
      candidate_matches: matches
    )
  end

  def apply!
    preview_result = preview
    return preview_result unless preview_result.success

    skipped_row = @skipped_row
    corrected = preview_result.corrected_values
    action = preview_result.suggested_action

    ActiveRecord::Base.transaction do
      target_voter, before_values, after_values =
        if action == "create"
          voter = create_voter!(corrected)
          [ voter, nil, serialized_voter_values(voter) ]
        else
          voter, before, after = update_voter!(preview_result.target_voter, corrected)
          [ voter, before, after ]
        end

      skipped_row.update!(
        corrected_values: corrected.compact,
        resolution_status: action == "create" ? "resolved_created" : "resolved_updated",
        resolution_action: action,
        resolved_at: Time.current,
        resolved_by_user: @actor_user,
        resolved_gec_voter: target_voter,
        resolution_details: {
          "target_gec_voter_id" => target_voter.id,
          "before_values" => before_values,
          "after_values" => after_values
        }
      )

      AuditLog.create!(
        auditable: skipped_row,
        actor_user: @actor_user,
        action: "gec_import_skipped_row_resolved",
        changed_data: {
          action: action,
          import_id: skipped_row.gec_import_id,
          row_number: skipped_row.row_number,
          target_gec_voter_id: target_voter.id,
          corrected_values: corrected.compact,
          before_values: before_values,
          after_values: after_values
        },
        metadata: {
          source: "gec_skipped_row_resolution",
          import_id: skipped_row.gec_import_id,
          skipped_row_id: skipped_row.id
        }
      )
    end

    build_result(
      success: true,
      status: skipped_row.reload.resolution_status,
      corrected_values: skipped_row.corrected_values,
      suggested_action: skipped_row.resolution_action,
      target_voter: skipped_row.resolved_gec_voter,
      skipped_row: skipped_row
    )
  end

  def dismiss!
    return already_resolved_result unless @skipped_row.resolution_status == "pending"

    @skipped_row.update!(
      resolution_status: "dismissed",
      resolution_action: "dismiss",
      resolved_at: Time.current,
      resolved_by_user: @actor_user,
      resolution_details: {
        "dismissed_by_user_id" => @actor_user&.id
      }
    )

    AuditLog.create!(
      auditable: @skipped_row,
      actor_user: @actor_user,
      action: "gec_import_skipped_row_dismissed",
      changed_data: {
        import_id: @skipped_row.gec_import_id,
        row_number: @skipped_row.row_number
      },
      metadata: {
        source: "gec_skipped_row_resolution",
        import_id: @skipped_row.gec_import_id,
        skipped_row_id: @skipped_row.id
      }
    )

    build_result(
      success: true,
      status: @skipped_row.resolution_status,
      corrected_values: @skipped_row.corrected_values,
      suggested_action: @skipped_row.resolution_action,
      skipped_row: @skipped_row
    )
  end

  private

  def already_resolved_result
    build_result(
      success: false,
      status: "already_resolved",
      errors: [ "This skipped row has already been resolved." ],
      corrected_values: @skipped_row.corrected_values.presence || base_corrected_values
    )
  end

  def normalize_corrected_values
    values = base_corrected_values.merge(symbolize_attributes(@attributes))

    {
      first_name: values[:first_name].to_s.strip.presence,
      last_name: values[:last_name].to_s.strip.presence,
      village_name: GecImportService.normalize_village_name(values[:village_name]),
      voter_registration_number: GecImportService.normalize_voter_registration_number(values[:voter_registration_number]),
      birth_year: GecImportService.parse_birth_year(values[:birth_year]),
      dob: parse_optional_dob(values[:dob]),
      source_name: @skipped_row.source_name
    }
  end

  def base_corrected_values
    {
      first_name: @skipped_row.first_name,
      last_name: @skipped_row.last_name,
      village_name: @skipped_row.village_name,
      voter_registration_number: @skipped_row.voter_registration_number,
      birth_year: @skipped_row.birth_year,
      dob: @skipped_row.dob
    }
  end

  def validate_corrected_values(corrected)
    errors = []
    errors << "First name is required." if corrected[:first_name].blank?
    errors << "Last name is required." if corrected[:last_name].blank?
    errors << "Village is required." if corrected[:village_name].blank?
    errors << "Birth year or date of birth is required." if corrected[:birth_year].blank? && corrected[:dob].blank?
    errors
  end

  def resolve_vrn_candidate(corrected)
    vrn = corrected[:voter_registration_number]
    return [ nil, [] ] if vrn.blank?

    matches = GecVoter.where(voter_registration_number: vrn).limit(2).to_a
    return [ nil, [] ] if matches.empty?

    if matches.size > 1
      return [ nil, [ "This voter registration number is attached to multiple voter records and needs manual review outside this tool." ] ]
    end

    candidate = matches.first
    if GecImportService.trusted_vrn_match?(candidate, corrected.merge(dob_estimated: corrected[:dob].blank?))
      [ candidate, [] ]
    else
      [ nil, [ "This voter registration number belongs to a different voter record. Review the correction before applying it." ] ]
    end
  end

  def build_candidate_matches(corrected, preferred_voter:)
    match_entries = GecVoter.find_matches(
      first_name: corrected[:first_name],
      last_name: corrected[:last_name],
      dob: corrected[:dob],
      birth_year: corrected[:birth_year],
      village_name: corrected[:village_name]
    )

    by_voter_id = {}
    match_entries.each do |entry|
      by_voter_id[entry[:gec_voter].id] ||= entry
    end

    if preferred_voter
      by_voter_id[preferred_voter.id] ||= {
        gec_voter: preferred_voter,
        confidence: :exact,
        match_type: :vrn_match,
        match_count: 1
      }
    end

    by_voter_id.values.sort_by do |entry|
      [ confidence_rank(entry[:confidence]), entry[:gec_voter].last_name.to_s, entry[:gec_voter].first_name.to_s ]
    end
  end

  def safe_single_match?(entry)
    %i[exact high].include?(entry[:confidence]) && entry[:match_count].to_i == 1
  end

  def confidence_rank(confidence)
    case confidence.to_sym
    when :exact then 0
    when :high then 1
    when :medium then 2
    else 3
    end
  end

  def create_voter!(corrected)
    GecVoter.create!(
      first_name: corrected[:first_name],
      last_name: corrected[:last_name],
      village_name: corrected[:village_name],
      voter_registration_number: corrected[:voter_registration_number],
      birth_year: corrected[:birth_year] || corrected[:dob]&.year,
      dob: corrected[:dob],
      gec_list_date: @skipped_row.gec_import.gec_list_date,
      imported_at: Time.current,
      status: "active"
    )
  end

  def update_voter!(voter, corrected)
    before_values = serialized_voter_values(voter)
    attrs = {
      first_name: corrected[:first_name],
      last_name: corrected[:last_name],
      village_name: corrected[:village_name],
      voter_registration_number: corrected[:voter_registration_number] || voter.voter_registration_number,
      birth_year: corrected[:birth_year] || corrected[:dob]&.year || voter.birth_year,
      dob: corrected[:dob] || voter.dob,
      gec_list_date: @skipped_row.gec_import.gec_list_date,
      imported_at: Time.current,
      status: "active",
      removed_at: nil,
      removal_detected_by_import_id: nil
    }

    if voter.village_name.to_s.strip.downcase != corrected[:village_name].to_s.strip.downcase
      attrs[:previous_village_name] = voter.village_name
      attrs[:village_id] = nil
    end

    voter.update!(attrs)
    [ voter, before_values, serialized_voter_values(voter) ]
  end

  def serialized_voter_values(voter)
    {
      "first_name" => voter.first_name,
      "last_name" => voter.last_name,
      "village_name" => voter.village_name,
      "voter_registration_number" => voter.voter_registration_number,
      "birth_year" => voter.birth_year,
      "dob" => voter.dob
    }
  end

  def parse_optional_dob(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  def symbolize_attributes(attrs)
    attrs.each_with_object({}) do |(key, value), memo|
      memo[key.to_sym] = value
    end
  end

  def build_result(success:, status:, errors: [], corrected_values:, suggested_action: nil, target_voter: nil, candidate_matches: [], skipped_row: @skipped_row)
    Result.new(
      success: success,
      status: status,
      errors: errors,
      message: errors.first,
      corrected_values: corrected_values,
      suggested_action: suggested_action,
      target_voter: target_voter,
      candidate_matches: candidate_matches,
      skipped_row: skipped_row
    )
  end
end
