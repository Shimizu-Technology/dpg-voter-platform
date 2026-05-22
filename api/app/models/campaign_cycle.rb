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
  rescue ActiveRecord::RecordNotUnique
    active.ordered.first || activate_default_cycle!(find_by!(name: default_cycle_name))
  end

  def self.create_or_find_default_cycle!
    cycle = find_by(name: default_cycle_name)
    return activate_default_cycle!(cycle) if cycle

    transaction(requires_new: true) do
      create!(
        name: default_cycle_name,
        cycle_type: "organizing",
        start_date: Date.current.beginning_of_year,
        end_date: Date.current.end_of_year,
        status: "active",
        monthly_quota_target: 0,
        settings: {}
      )
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    activate_default_cycle!(find_by!(name: default_cycle_name))
  end

  def self.activate_default_cycle!(cycle)
    return cycle if cycle.status == "active"

    cycle.update!(status: "active")
    cycle
  end

  def self.default_cycle_name
    "#{Date.current.year} DPG Organizing Cycle"
  end

  private

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end
end
