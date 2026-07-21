# frozen_string_literal: true

class CreateElectionEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :election_events do |t|
      t.string :name, null: false
      t.string :election_type, null: false, default: "general"
      t.date :election_date, null: false
      t.string :status, null: false, default: "setup"
      t.references :gec_import, foreign_key: true
      t.datetime :activated_at
      t.references :activated_by_user, foreign_key: { to_table: :users }
      t.datetime :closed_at
      t.references :closed_by_user, foreign_key: { to_table: :users }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :election_events, :status
    add_index :election_events, [ :election_date, :name ]
    add_index :election_events, :status, unique: true, where: "status = 'active'", name: "index_election_events_unique_active"
  end
end
