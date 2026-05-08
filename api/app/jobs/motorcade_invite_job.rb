# frozen_string_literal: true

class MotorcadeInviteJob < ApplicationJob
  queue_as :default

  def perform(event_id:)
    event = Event.find_by(id: event_id)
    return unless event&.event_type == "motorcade"

    supporters = Supporter.active.motorcade_available
    supporters = supporters.where(village_id: event.village_id) if event.village_id.present?

    supporters.find_each do |supporter|
      event.event_rsvps.find_or_create_by!(supporter: supporter) do |rsvp|
        rsvp.rsvp_status = "invited"
      end

      SmsService.motorcade_notification(supporter, event) if supporter.contact_number.present?
      sleep(0.1)
    rescue StandardError => e
      Rails.logger.error("[MotorcadeInviteJob] Failed for supporter #{supporter&.id}: #{e.message}")
    end
  end
end
