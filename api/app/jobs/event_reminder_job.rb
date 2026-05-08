# frozen_string_literal: true

# Sends reminders to all confirmed RSVPs for an event.
# Schedule this to run the day before an event.
class EventReminderJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find_by(id: event_id)
    return unless event

    rsvps = event.event_rsvps.where(rsvp_status: "confirmed").includes(:supporter)
    sent = 0

    rsvps.find_each do |rsvp|
      next if rsvp.supporter.contact_number.blank?

      SmsService.event_reminder(rsvp.supporter, event)
      sent += 1
      sleep(0.1) # Rate limiting
    end

    Rails.logger.info("[EventReminderJob] Sent #{sent} reminders for event #{event.name}")
  end
end
