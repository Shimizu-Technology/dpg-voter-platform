# frozen_string_literal: true

class ElectionTurnoutUpdateService
  Result = Struct.new(:success?, :record, :errors, keyword_init: true)

  def initialize(election_event:, gec_voter:, actor_user:, turnout_status:, note: nil, source:, observation_precinct: nil)
    @election_event = election_event
    @gec_voter = gec_voter
    @actor_user = actor_user
    @turnout_status = turnout_status
    @note = note
    @source = source
    @observation_precinct = observation_precinct
  end

  def call
    record = ElectionTurnoutRecord.for(election_event: election_event, gec_voter: gec_voter)
    original = record.attributes.slice("turnout_status", "turnout_note", "turnout_source", "turnout_updated_by_user_id", "turnout_updated_at")
    record.assign_attributes(turnout_attrs)
    failure_result = nil

    ActiveRecord::Base.transaction do
      unless record.save
        failure_result = Result.new(success?: false, record: record, errors: record.errors.full_messages)
        raise ActiveRecord::Rollback
      end

      if election_event.status == "active"
        legacy_result = sync_current_turnout_fields
        unless legacy_result.success?
          failure_result = Result.new(success?: false, record: record, errors: legacy_result.errors.presence || [ "Current turnout sync failed" ])
          raise ActiveRecord::Rollback
        end
      end

      log_turnout_audit!(record, original)
    end

    return failure_result if failure_result

    Result.new(success?: true, record: record, errors: [])
  end

  private

  attr_reader :election_event, :gec_voter, :actor_user, :turnout_status, :note, :source, :observation_precinct

  def turnout_attrs
    {
      turnout_status: turnout_status,
      turnout_note: normalized_turnout_note,
      turnout_source: source,
      turnout_updated_by_user: actor_user,
      turnout_updated_at: Time.current,
      observation_precinct: observation_precinct,
      observation_precinct_number: observation_precinct&.number,
      observation_village_name: observation_precinct&.village&.name,
      registered_precinct: gec_voter.precinct,
      registered_precinct_number: gec_voter.precinct_number || gec_voter.precinct&.number,
      registered_village_name: gec_voter.village_name || gec_voter.village&.name,
      supporter: Supporter.where(gec_voter_id: gec_voter.id).order(:id).first
    }
  end

  def sync_current_turnout_fields
    GecVoterTurnoutService.new(
      gec_voter: gec_voter,
      actor_user: actor_user,
      turnout_status: turnout_status,
      note: normalized_turnout_note,
      source: source,
      observation_precinct: observation_precinct
    ).call
  end

  def log_turnout_audit!(record, original)
    changed = {}
    original.each do |field, before|
      after = record.public_send(field)
      changed[field] = { from: before, to: after } if before != after
    end

    AuditLog.create!(
      auditable: record,
      actor_user: actor_user,
      action: "election_turnout_updated",
      changed_data: changed,
      metadata: {
        resource: "election_turnout_record",
        election_event_id: election_event.id,
        election_name: election_event.name,
        gec_voter_id: gec_voter.id,
        registered_precinct_id: gec_voter.precinct_id,
        observation_precinct_id: observation_precinct&.id,
        turnout_source: source,
        compliance_context: "dpg_operations_not_official_record"
      }
    )
  end

  def normalized_turnout_note
    plain_note = note.to_s.strip
    return plain_note if turnout_status != "observed_elsewhere" || observation_precinct.blank?

    observation_context = "Observed at Precinct #{observation_precinct.number}"
    observation_context += " (#{observation_precinct.village.name})" if observation_precinct.village&.name.present?
    return observation_context if plain_note.blank?

    "#{observation_context}. #{plain_note}"
  end
end
