# frozen_string_literal: true

class ElectionEvent < ApplicationRecord
  class InvalidTransition < StandardError; end

  STATUSES = %w[setup training active closed archived].freeze
  ELECTION_TYPES = %w[primary general runoff special other].freeze

  belongs_to :gec_import, optional: true
  belongs_to :activated_by_user, class_name: "User", optional: true
  belongs_to :training_started_by_user, class_name: "User", optional: true
  belongs_to :closed_by_user, class_name: "User", optional: true
  has_many :election_turnout_records, dependent: :destroy
  has_many :poll_reports, dependent: :nullify

  validates :name, presence: true
  validates :election_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :election_type, inclusion: { in: ELECTION_TYPES }

  scope :recent_first, -> { order(election_date: :desc, created_at: :desc) }
  scope :active, -> { where(status: "active") }
  scope :current, -> { where(status: %w[training active]) }
  scope :open_for_setup, -> { where(status: %w[setup training active]) }

  def self.active_event
    active.recent_first.first
  end

  def self.current_event
    current.order(Arel.sql("CASE status WHEN 'active' THEN 0 ELSE 1 END"), election_date: :desc, created_at: :desc).first
  end

  def activate!(actor_user:)
    raise InvalidTransition, "Only an election in setup can be activated" unless status == "setup"

    transition_to_current!(status: "active", actor_user: actor_user)
  end

  def start_training!(actor_user:)
    raise InvalidTransition, "Only an election in setup can begin training" unless status == "setup"

    transition_to_current!(status: "training", actor_user: actor_user)
  end

  def close!(actor_user:)
    update!(status: "closed", closed_at: Time.current, closed_by_user: actor_user)
  end

  def gec_list_date
    gec_import&.gec_list_date
  end

  def active_or_training?
    status.in?(%w[active training])
  end

  private

  def transition_to_current!(status:, actor_user:)
    transaction do
      attributes = { status: status }
      if status == "training"
        attributes.merge!(training_started_at: Time.current, training_started_by_user: actor_user)
      else
        attributes.merge!(activated_at: Time.current, activated_by_user: actor_user)
      end
      update!(attributes)
    end
  end
end
