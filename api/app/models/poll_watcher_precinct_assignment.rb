# frozen_string_literal: true

class PollWatcherPrecinctAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :precinct
  belongs_to :assigned_by_user, class_name: "User", optional: true

  validates :assigned_at, presence: true
  validates :precinct_id, uniqueness: { scope: :user_id }
  validate :user_is_poll_watcher

  before_validation :default_assigned_at

  private

  def default_assigned_at
    self.assigned_at ||= Time.current
  end

  def user_is_poll_watcher
    return if user&.poll_watcher?

    errors.add(:user, "must be a field observer")
  end
end
