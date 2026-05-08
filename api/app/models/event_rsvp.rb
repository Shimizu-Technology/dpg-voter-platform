class EventRsvp < ApplicationRecord
  belongs_to :event
  belongs_to :supporter
  belongs_to :checked_in_by, class_name: "User", foreign_key: :checked_in_by_id, optional: true

  validates :rsvp_status, inclusion: { in: %w[invited confirmed declined no_response] }
  validates :supporter_id, uniqueness: { scope: :event_id }

  scope :attended, -> { where(attended: true) }
  scope :no_shows, -> { where(rsvp_status: "confirmed", attended: false) }

  def check_in!(user)
    update!(attended: true, checked_in_at: Time.current, checked_in_by: user)
  end
end
