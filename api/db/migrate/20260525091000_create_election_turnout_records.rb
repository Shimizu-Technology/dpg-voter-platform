# frozen_string_literal: true

class CreateElectionTurnoutRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :election_turnout_records do |t|
      t.references :election_event, null: false, foreign_key: true
      t.references :gec_voter, null: false, foreign_key: true
      t.references :supporter, foreign_key: true
      t.references :registered_precinct, foreign_key: { to_table: :precincts }
      t.string :registered_precinct_number
      t.string :registered_village_name
      t.references :observation_precinct, foreign_key: { to_table: :precincts }
      t.string :observation_precinct_number
      t.string :observation_village_name
      t.string :turnout_status, null: false, default: "not_yet_voted"
      t.text :turnout_note
      t.string :turnout_source
      t.references :turnout_updated_by_user, foreign_key: { to_table: :users }
      t.datetime :turnout_updated_at
      t.timestamps
    end

    add_index :election_turnout_records, [ :election_event_id, :gec_voter_id ], unique: true, name: "index_election_turnout_unique_voter"
    add_index :election_turnout_records, [ :election_event_id, :turnout_status ], name: "index_election_turnout_on_event_status"
    add_index :election_turnout_records, [ :election_event_id, :registered_precinct_id ], name: "index_election_turnout_on_event_precinct"
    add_index :election_turnout_records, [ :election_event_id, :supporter_id ], name: "index_election_turnout_on_event_supporter"
  end
end
