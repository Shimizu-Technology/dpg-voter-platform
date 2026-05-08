# frozen_string_literal: true

class SmsBlast < ApplicationRecord
  STATUSES = %w[pending sending completed failed].freeze

  belongs_to :initiated_by, class_name: "User", foreign_key: :initiated_by_user_id

  validates :status, inclusion: { in: STATUSES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc).limit(20) }

  def progress_pct
    return 0 if total_recipients.nil? || total_recipients.zero?
    [ ((sent_count.to_i + failed_count.to_i) * 100.0 / total_recipients).round(1), 100.0 ].min
  end

  def finished?
    %w[completed failed].include?(status)
  end

  # NOTE: Available for per-message tracking (e.g., single SMS sends).
  # Not used by SmsBlastJob, which uses batch update_all instead.
  def increment_sent!
    self.class.where(id: id).update_all("sent_count = COALESCE(sent_count, 0) + 1")
  end

  def increment_failed!(error_msg = nil)
    self.class.where(id: id).update_all("failed_count = COALESCE(failed_count, 0) + 1")
    append_error(error_msg) if error_msg
  end

  def append_error(msg)
    # Atomic SQL append to avoid race conditions; cap at 50 entries
    self.class.where(id: id)
      .where("jsonb_array_length(COALESCE(error_log, '[]'::jsonb)) < 50")
      .update_all([ "error_log = COALESCE(error_log, '[]'::jsonb) || ?::jsonb", [ msg ].to_json ])
  end
end
