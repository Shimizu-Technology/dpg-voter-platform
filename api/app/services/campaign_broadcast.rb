# frozen_string_literal: true

# Broadcasts real-time updates to connected WebSocket clients.
# All events go to the "campaign_updates" stream with a `type` field
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

    # Poll watcher submitted a report
    def poll_report(report)
      precinct = report.precinct
      village = precinct.village
      registered = precinct.registered_voters || 0
      turnout_pct = registered > 0 ? (report.voter_count * 100.0 / registered).round(1) : 0

      broadcast(:poll_report, {
        report_id: report.id,
        precinct_id: precinct.id,
        precinct_number: precinct.number,
        village_id: village.id,
        village_name: village.name,
        voter_count: report.voter_count,
        report_type: report.report_type,
        turnout_pct: turnout_pct,
        notes: report.notes,
        reported_at: report.reported_at&.iso8601
      })
    end

    # Event check-in happened
    def event_check_in(event, supporter, rsvp)
      broadcast(:event_check_in, {
        event_id: event.id,
        event_name: event.name,
        supporter_name: supporter.print_name,
        attended_count: event.attended_count,
        invited_count: event.invited_count,
        checked_in_at: rsvp.checked_in_at&.iso8601
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
      ActionCable.server.broadcast("campaign_updates", {
        type: type,
        data: payload,
        timestamp: Time.current.iso8601
      })
    rescue => e
      Rails.logger.error("[CampaignBroadcast] Failed to broadcast #{type}: #{e.message}")
    end
  end
end
