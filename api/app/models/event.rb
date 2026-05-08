class Event < ApplicationRecord
  belongs_to :campaign
  belongs_to :village, optional: true
  has_many :event_rsvps, dependent: :destroy
  has_many :supporters, through: :event_rsvps

  validates :name, presence: true
  validates :event_type, inclusion: { in: %w[motorcade rally fundraiser meeting other] }
  validates :status, inclusion: { in: %w[upcoming active completed cancelled] }
  validates :date, presence: true

  scope :upcoming, -> { where(status: "upcoming").order(date: :asc) }
  scope :completed, -> { where(status: "completed") }

  def invited_count
    event_rsvps.count
  end

  def confirmed_count
    event_rsvps.where(rsvp_status: "confirmed").count
  end

  def attended_count
    event_rsvps.where(attended: true).count
  end

  def show_up_rate
    total = invited_count
    return 0 if total == 0
    ((attended_count.to_f / total) * 100).round(1)
  end

  def quota_met?
    return true if quota.nil? || quota == 0
    attended_count >= quota
  end
end
