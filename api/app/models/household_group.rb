class HouseholdGroup < ApplicationRecord
  belongs_to :village
  has_many :supporters, -> { order(household_primary: :desc, created_at: :asc) }, dependent: :nullify

  validates :village_id, presence: true
end
