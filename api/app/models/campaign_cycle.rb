# frozen_string_literal: true

class CampaignCycle < ApplicationRecord
  STATUSES = %w[active completed archived].freeze
  CYCLE_TYPES = %w[primary general special organizing].freeze

  has_many :quota_periods, dependent: :restrict_with_error

  validates :name, :cycle_type, :start_date, :end_date, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cycle_type, inclusion: { in: CYCLE_TYPES }
  validate :end_date_on_or_after_start_date

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(start_date: :desc, id: :desc) }

  def self.current_or_create_default!
    active.ordered.first || create!(
      name: "#{Date.current.year} DPG Organizing Cycle",
      cycle_type: "organizing",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active",
      monthly_quota_target: 0,
      settings: {}
    )
  end

  private

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end
end
