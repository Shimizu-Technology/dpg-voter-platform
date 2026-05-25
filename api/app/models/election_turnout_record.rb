# frozen_string_literal: true

class ElectionTurnoutRecord < ApplicationRecord
  TURNOUT_STATUSES = GecVoter::TURNOUT_STATUSES
  TURNOUT_SOURCES = GecVoter::TURNOUT_SOURCES

  belongs_to :election_event
  belongs_to :gec_voter
  belongs_to :supporter, optional: true
  belongs_to :registered_precinct, class_name: "Precinct", optional: true
  belongs_to :observation_precinct, class_name: "Precinct", optional: true
  belongs_to :turnout_updated_by_user, class_name: "User", optional: true

  validates :turnout_status, inclusion: { in: TURNOUT_STATUSES }
  validates :turnout_source, inclusion: { in: TURNOUT_SOURCES }, allow_blank: true
  validates :gec_voter_id, uniqueness: { scope: :election_event_id }

  scope :voted, -> { where(turnout_status: "voted") }
  scope :not_yet_voted, -> { where(turnout_status: "not_yet_voted") }
  scope :observed_elsewhere, -> { where(turnout_status: "observed_elsewhere") }

  def self.for(election_event:, gec_voter:)
    find_or_initialize_by(election_event: election_event, gec_voter: gec_voter) do |record|
      apply_voter_defaults(record, gec_voter)
      record.supporter = Supporter.where(gec_voter_id: gec_voter.id).order(:id).first
    end
  end

  def self.build_for_display(election_event:, gec_voter:)
    new(election_event: election_event, gec_voter: gec_voter).tap do |record|
      apply_voter_defaults(record, gec_voter)
    end
  end

  def self.apply_voter_defaults(record, gec_voter)
    record.registered_precinct = gec_voter.precinct
    record.registered_precinct_number = gec_voter.precinct_number || gec_voter.precinct&.number
    record.registered_village_name = gec_voter.village_name || gec_voter.village&.name
    record.turnout_status = TURNOUT_STATUSES.include?(gec_voter.turnout_status) ? gec_voter.turnout_status : "not_yet_voted"
  end
end
