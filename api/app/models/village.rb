# frozen_string_literal: true

class Village < ApplicationRecord
  belongs_to :district, optional: true
  has_many :precincts, dependent: :destroy
  has_many :blocks, dependent: :destroy
  has_many :supporters, dependent: :destroy
  has_many :quotas, dependent: :destroy
  has_many :village_quotas, dependent: :destroy
  has_many :events, dependent: :nullify
  has_many :referral_codes, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  # Registered voters is now derived from precincts (single source of truth).
  # This method is used everywhere village.registered_voters was previously a column.
  def registered_voters
    if precincts.loaded?
      precincts.sum { |p| p.registered_voters.to_i }
    else
      precincts.sum(:registered_voters)
    end
  end

  # Precinct count is also derived.
  def precinct_count
    if precincts.loaded?
      precincts.size
    else
      precincts.count
    end
  end

  def supporter_count
    supporters.active.count
  end

  def quota_progress(campaign_id = nil)
    quota = quotas.where(campaign_id: campaign_id).order(target_date: :desc).first
    return nil unless quota
    { target: quota.target_count, current: supporter_count, percentage: quota.target_count > 0 ? (supporter_count * 100.0 / quota.target_count).round(1) : 0 }
  end
end
