class Precinct < ApplicationRecord
  belongs_to :village
  has_many :supporters, dependent: :nullify
  has_many :poll_reports, dependent: :destroy
  has_many :poll_watcher_precinct_assignments, dependent: :destroy
  has_many :assigned_poll_watchers, through: :poll_watcher_precinct_assignments, source: :user

  validates :number, presence: true
  validates :number, uniqueness: { scope: :village_id, case_sensitive: false }
  validates :registered_voters, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
