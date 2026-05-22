# frozen_string_literal: true

class VillageQuota < ApplicationRecord
  belongs_to :quota_period
  belongs_to :village

  validates :target, numericality: { greater_than_or_equal_to: 0 }
  validates :village_id, uniqueness: { scope: :quota_period_id }
end
