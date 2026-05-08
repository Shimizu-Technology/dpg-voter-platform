class GecVoterTurnoutService
  Result = Struct.new(:success?, :gec_voter, :errors, keyword_init: true)

  def initialize(gec_voter:, actor_user:, turnout_status:, note: nil, source:, observation_precinct: nil)
    @gec_voter = gec_voter
    @actor_user = actor_user
    @turnout_status = turnout_status
    @note = note
    @source = source
    @observation_precinct = observation_precinct
  end

  def call
    gec_voter.assign_attributes(
      turnout_status: turnout_status,
      turnout_note: normalized_turnout_note,
      turnout_updated_at: Time.current,
      turnout_updated_by_user: actor_user,
      turnout_source: source
    )

    ActiveRecord::Base.transaction do
      unless gec_voter.save
        return Result.new(success?: false, gec_voter: gec_voter, errors: gec_voter.errors.full_messages)
      end

      changed_data = gec_voter.saved_changes.slice(
        "turnout_status",
        "turnout_note",
        "turnout_updated_at",
        "turnout_updated_by_user_id",
        "turnout_source"
      )
      log_turnout_audit!(changed_data)
      sync_linked_supporters!
    end

    Result.new(success?: true, gec_voter: gec_voter, errors: [])
  end

  private

  attr_reader :gec_voter, :actor_user, :turnout_status, :note, :source, :observation_precinct

  def sync_linked_supporters!
    attrs = {
      precinct_id: gec_voter.precinct_id,
      turnout_status: gec_voter.turnout_status,
      turnout_note: gec_voter.turnout_note,
      turnout_updated_at: gec_voter.turnout_updated_at,
      turnout_updated_by_user_id: gec_voter.turnout_updated_by_user_id,
      turnout_source: gec_voter.turnout_source,
      updated_at: Time.current
    }

    Supporter.where(gec_voter_id: gec_voter.id).update_all(attrs)
  end

  def log_turnout_audit!(changed_data)
    return if changed_data.blank?

    AuditLog.create!(
      auditable: gec_voter,
      actor_user: actor_user,
      action: "turnout_updated",
      changed_data: normalize_changed_data(changed_data),
      metadata: {
        resource: "gec_voter_turnout",
        precinct_id: gec_voter.precinct_id,
        observation_precinct_id: observation_precinct&.id,
        observation_precinct_number: observation_precinct&.number,
        observation_village_name: observation_precinct&.village&.name,
        turnout_source: gec_voter.turnout_source,
        linked_supporter_ids: Supporter.where(gec_voter_id: gec_voter.id).pluck(:id),
        compliance_context: "campaign_operations_not_official_record"
      }
    )
  end

  def normalized_turnout_note
    plain_note = note.to_s.strip
    return plain_note if turnout_status != "observed_elsewhere" || observation_precinct.blank?

    observation_context = "Observed at Precinct #{observation_precinct.number}"
    if observation_precinct.village&.name.present?
      observation_context += " (#{observation_precinct.village.name})"
    end

    return observation_context if plain_note.blank?

    "#{observation_context}. #{plain_note}"
  end

  def normalize_changed_data(changed_data)
    changed_data.each_with_object({}) do |(field, value), output|
      if value.is_a?(Array) && value.length == 2
        output[field] = { from: value[0], to: value[1] }
      else
        output[field] = { from: nil, to: value }
      end
    end
  end
end
