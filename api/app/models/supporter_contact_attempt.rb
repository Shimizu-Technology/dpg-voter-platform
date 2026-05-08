class SupporterContactAttempt < ApplicationRecord
  OUTCOMES = %w[attempted reached wrong_number unavailable refused].freeze
  CHANNELS = %w[call sms in_person].freeze

  belongs_to :supporter
  belongs_to :recorded_by_user, class_name: "User"
  has_many :audit_logs, as: :auditable, dependent: :destroy

  validates :outcome, presence: true, inclusion: { in: OUTCOMES }
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :recorded_at, presence: true
end
