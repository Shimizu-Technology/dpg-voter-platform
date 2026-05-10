# frozen_string_literal: true

# Broadcasts real-time updates to connected WebSocket clients.
# All events go to the "dpg_updates" stream with a `type` field
# so the frontend can filter which events it cares about.
class CampaignBroadcast
  class << self
    # New supporter signed up
    def new_supporter(supporter)
      broadcast(:new_supporter, {
        supporter_id: supporter.id,
        first_name: supporter.first_name,
        last_name: supporter.last_name,
        print_name: supporter.print_name,
        village_id: supporter.village_id,
        village_name: supporter.village&.name,
        source: supporter.source,
        created_at: supporter.created_at&.iso8601
      })
    end

    # Supporter updated (verification/lifecycle/assignment edits)
    def supporter_updated(supporter, action: "updated")
      broadcast(:supporter_updated, {
        supporter_id: supporter.id,
        print_name: supporter.print_name,
        village_id: supporter.village_id,
        village_name: supporter.village&.name,
        precinct_id: supporter.precinct_id,
        status: supporter.status,
        verification_status: supporter.verification_status,
        potential_duplicate: supporter.potential_duplicate,
        action: action,
        updated_at: supporter.updated_at&.iso8601
      })
    end

    # Dashboard stats refresh (can be triggered periodically or on demand)
    def stats_update(stats)
      broadcast(:stats_update, stats)
    end

    private

    def broadcast(type, payload)
      ActionCable.server.broadcast("dpg_updates", {
        type: type,
        data: payload,
        timestamp: Time.current.iso8601
      })
    rescue => e
      Rails.logger.error("[CampaignBroadcast] Failed to broadcast #{type}: #{e.message}")
    end
  end
end
