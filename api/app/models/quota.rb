class Quota < ApplicationRecord
  self.table_name = "quotas"
  belongs_to :campaign
  belongs_to :village, optional: true
  belongs_to :district, optional: true

  validates :target_count, presence: true, numericality: { greater_than: 0 }
  validates :period, inclusion: { in: %w[weekly monthly quarterly] }

  validate :must_have_village_or_district

  private

  def must_have_village_or_district
    if village_id.blank? && district_id.blank?
      errors.add(:base, "Must belong to a village or district")
    end
  end
end
