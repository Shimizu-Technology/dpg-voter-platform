# frozen_string_literal: true

class EmailBlast < ApplicationRecord
  STATUSES = %w[pending sending completed failed].freeze

  belongs_to :initiated_by, class_name: "User", foreign_key: :initiated_by_user_id
  has_many :outreach_deliveries, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :subject, presence: true

  scope :recent, -> { order(created_at: :desc).limit(20) }

  def progress_pct
    return 0 if total_recipients.to_i.zero?

    [ ((sent_count.to_i + failed_count.to_i) * 100.0 / total_recipients).round(1), 100.0 ].min
  end

  def finished?
    %w[completed failed].include?(status)
  end

  def append_error(msg)
    self.class.where(id: id)
      .where("jsonb_array_length(COALESCE(error_log, '[]'::jsonb)) < 50")
      .update_all([ "error_log = COALESCE(error_log, '[]'::jsonb) || ?::jsonb", [ msg ].to_json ])
  end
end
