# frozen_string_literal: true

class CampaignCycle < ApplicationRecord
  STATUSES = %w[active completed archived].freeze
  CYCLE_TYPES = %w[primary general special organizing].freeze

  has_many :quota_periods, dependent: :restrict_with_error

  validates :name, :cycle_type, :start_date, :end_date, :status, presence: true
  validates :name, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :cycle_type, inclusion: { in: CYCLE_TYPES }
  validate :end_date_on_or_after_start_date

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(start_date: :desc, id: :desc) }

  def self.current_or_create_default!
    active.ordered.first || create_or_find_default_cycle!
  end

  def self.create_or_find_default_cycle!
    default_name = "#{Date.current.year} DPG Organizing Cycle"

    create_or_find_by!(name: default_name) do |cycle|
      cycle.cycle_type = "organizing"
      cycle.start_date = Date.current.beginning_of_year
      cycle.end_date = Date.current.end_of_year
      cycle.status = "active"
      cycle.monthly_quota_target = 0
      cycle.settings = {}
    end
  end

  private

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end
end
