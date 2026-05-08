# frozen_string_literal: true

# Single channel for all real-time campaign updates.
# Clients subscribe and receive typed events they can filter on.
class CampaignChannel < ApplicationCable::Channel
  def subscribed
    reject unless realtime_access_allowed?
    stream_from "campaign_updates"
  end

  def unsubscribed
    # cleanup if needed
  end

  private

  def realtime_access_allowed?
    return false unless current_user

    current_user.admin? || current_user.coordinator? || current_user.chief? || current_user.poll_watcher?
  end
end
