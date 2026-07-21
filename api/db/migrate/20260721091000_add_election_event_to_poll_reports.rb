# frozen_string_literal: true

class AddElectionEventToPollReports < ActiveRecord::Migration[8.1]
  def change
    add_reference :poll_reports, :election_event, foreign_key: true
    add_index :poll_reports,
      [ :election_event_id, :precinct_id, :reported_at ],
      name: "index_poll_reports_on_event_precinct_reported_at"
  end
end
