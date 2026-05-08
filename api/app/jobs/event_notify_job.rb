# frozen_string_literal: true

class EventNotifyJob < ApplicationJob
  queue_as :default

  def perform(event_id:, notification_type: "rsvp")
    event = Event.find_by(id: event_id)
    return unless event

    rsvps = event.event_rsvps.includes(:supporter)
    rsvps = rsvps.where(rsvp_status: "confirmed") if notification_type == "reminder"

    rsvps.find_each do |rsvp|
      supporter = rsvp.supporter
      next if supporter.contact_number.blank?

      case notification_type
      when "rsvp"
        SmsService.event_rsvp_confirmation(supporter, event)
      when "reminder"
        SmsService.event_reminder(supporter, event)
      when "motorcade"
        SmsService.motorcade_notification(supporter, event)
      end

      sleep(0.1)
    rescue StandardError => e
      Rails.logger.error("[EventNotifyJob] Failed for supporter #{supporter&.id}: #{e.message}")
    end
  end
end
