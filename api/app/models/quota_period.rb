# frozen_string_literal: true

class QuotaPeriod < ApplicationRecord
  STATUSES = %w[open submitted closed].freeze

  belongs_to :campaign_cycle
  has_many :village_quotas, dependent: :destroy
  has_many :supporters, dependent: :nullify

  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :due_date, presence: true
  validates :quota_target, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :current, -> { where("start_date <= ? AND end_date >= ?", Date.current, Date.current) }
  scope :upcoming, -> { where("start_date > ?", Date.current).order(:start_date) }
  scope :past, -> { where("end_date < ?", Date.current).order(start_date: :desc) }

  def editable?
    status == "open" && start_date <= Date.current && end_date >= Date.current
  end

  def locked?
    !editable?
  end

  # Supporters credited to this quota period.
  # New approvals are stamped with quota_period_id. Older approved rows fall back
  # to their review timestamp so existing production/test data still credits the
  # month in which the data team approved them.
  def credited_supporters
    base = Supporter.working_supporters

    base.where(quota_period_id: id).or(
      base.where(
        quota_period_id: nil,
        reviewed_at: start_date.beginning_of_day..end_date.end_of_day
      )
    )
  end

  # Backward-compatible alias used by current controllers/serializers.
  def eligible_supporters
    credited_supporters
  end

  def matched_supporters
    credited_supporters.where(verification_status: "verified")
  end

  # Count supporters credited toward this period's quota progress.
  def eligible_count
    credited_supporters.count
  end

  def matched_count
    matched_supporters.count
  end

  # Count all supporters assigned/credited to this period.
  def total_assigned
    credited_supporters.count
  end

  # Period-specific village targets are the long-term direction, but until the
  # quota settings UI becomes month-aware we must also honor the existing
  # campaign-level quota rows as the source of truth.
  def effective_village_targets(village_ids: nil, include_legacy_fallback: editable?)
    period_scope = village_quotas
    period_scope = period_scope.where(village_id: village_ids) if village_ids.present?
    period_targets = period_scope.group(:village_id).sum(:target)

    return period_targets unless include_legacy_fallback

    campaign = Campaign.active.first
    return period_targets if campaign.blank?

    legacy_scope = Quota.where(campaign: campaign)
    legacy_scope = legacy_scope.where(village_id: village_ids) if village_ids.present?
    legacy_targets = legacy_scope.group(:village_id).sum(:target_count)

    legacy_targets.merge(period_targets)
  end

  def effective_quota_target
    total = effective_village_targets.values.sum
    total.positive? ? total : quota_target
  end

  # Per-village breakdown — single query for all village counts
  def village_breakdown(include_legacy_fallback: editable?)
    targets_by_village = effective_village_targets(include_legacy_fallback: include_legacy_fallback)
    credited_by_village = credited_supporters.group(:village_id).count
    matched_by_village = matched_supporters.group(:village_id).count

    Village.where(id: targets_by_village.keys).order(:name).map do |village|
      eligible = credited_by_village[village.id] || 0
      matched = matched_by_village[village.id] || 0
      target = targets_by_village[village.id] || 0

      {
        village_id: village.id,
        village_name: village.name,
        target: target,
        eligible: eligible,
        matched: matched,
        progress_pct: target > 0 ? (eligible * 100.0 / target).round(1) : 0
      }
    end
  end

  # Snapshot counts at submission time
  def submit!
    ActiveRecord::Base.transaction do
      breakdown = village_breakdown
      village_quota_map = village_quotas.index_by(&:village_id)
      breakdown.each do |entry|
        vq = village_quota_map[entry[:village_id]]
        next unless vq

        vq.update!(submitted_count: entry[:eligible])
      end

      update!(
        status: "submitted",
        submission_summary: {
          submitted_at: Time.current.iso8601,
          total_eligible: eligible_count,
          total_matched: matched_count,
          total_assigned: total_assigned,
          village_breakdown: breakdown
        }
      )
    end
  end

  # Days until due
  def days_until_due
    (due_date - Date.current).to_i
  end

  def overdue?
    status == "open" && Date.current > due_date
  end

  def due_soon?
    status == "open" && days_until_due.between?(0, 7)
  end

  # Returns the last Monday of the given month/year.
  # Per Trisha (Feb 26, 2026): GEC quota deadline is last Monday of each month.
  # Example: last_monday_of_month(2026, 2) => Date.new(2026, 2, 23)
  def self.last_monday_of_month(year, month)
    # Start at last day of month and walk back to Monday
    last_day = Date.new(year, month, -1)
    days_since_monday = last_day.wday == 0 ? 6 : last_day.wday - 1
    last_day - days_since_monday
  end
end
