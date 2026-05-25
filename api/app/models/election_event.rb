# frozen_string_literal: true

class ElectionEvent < ApplicationRecord
  STATUSES = %w[setup training active closed archived].freeze
  ELECTION_TYPES = %w[primary general runoff special other].freeze

  belongs_to :gec_import, optional: true
  belongs_to :activated_by_user, class_name: "User", optional: true
  belongs_to :closed_by_user, class_name: "User", optional: true
  has_many :election_turnout_records, dependent: :destroy

  validates :name, presence: true
  validates :election_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :election_type, inclusion: { in: ELECTION_TYPES }

  scope :recent_first, -> { order(election_date: :desc, created_at: :desc) }
  scope :active, -> { where(status: "active") }
  scope :open_for_setup, -> { where(status: %w[setup training active]) }

  def self.active_event
    active.recent_first.first
  end

  def activate!(actor_user:)
    transaction do
      closed_at = Time.current
      self.class.where(status: "active").where.not(id: id).update_all(
        status: "closed",
        closed_at: closed_at,
        closed_by_user_id: actor_user&.id,
        updated_at: closed_at
      )
      update!(status: "active", activated_at: Time.current, activated_by_user: actor_user)
    end
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
end
