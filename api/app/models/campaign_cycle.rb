# frozen_string_literal: true

class CampaignCycle < ApplicationRecord
  CYCLE_TYPES = %w[primary general special].freeze
  STATUSES = %w[active completed archived].freeze

  has_many :quota_periods, dependent: :destroy

  validates :name, presence: true
  validates :cycle_type, inclusion: { in: CYCLE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }
  scope :current, -> { active.where("start_date <= ? AND end_date >= ?", Date.current, Date.current) }

  # Default due day for quota submissions (configurable via settings)
  def due_day
    settings&.dig("due_day") || 23
  end

  # Generate quota periods for this cycle (monthly by default)
  def generate_periods!(village_targets: {})
    current_date = start_date.beginning_of_month

    while current_date < end_date
      period_end = current_date.end_of_month
      period_end = end_date if period_end > end_date
      due = Date.new(current_date.year, current_date.month, [ due_day, current_date.end_of_month.day ].min)

      period = quota_periods.find_or_create_by!(start_date: current_date) do |p|
        p.name = current_date.strftime("%B %Y")
        p.end_date = period_end
        p.due_date = due
        p.quota_target = monthly_quota_target || 6000
      end

      # Create village quotas if targets provided
      village_targets.each do |village_id, target|
        period.village_quotas.find_or_create_by!(village_id: village_id) do |vq|
          vq.target = target
        end
      end

      current_date = current_date.next_month.beginning_of_month
    end
  end

  # Get the current quota period (based on today's date)
  def current_period
    quota_periods.where("start_date <= ? AND end_date >= ?", Date.current, Date.current).first
  end

  def self.current_quota_period
    current.order(start_date: :desc, id: :desc).first&.current_period
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date

    errors.add(:end_date, "must be after start date") if end_date <= start_date
  end
end
