class Campaign < ApplicationRecord
  has_many :districts, dependent: :destroy
  has_many :quotas, dependent: :destroy
  has_many :events, dependent: :destroy

  validates :name, presence: true
  validates :election_year, presence: true
  validates :status, inclusion: { in: %w[active archived draft] }

  scope :active, -> { where(status: "active") }
end
