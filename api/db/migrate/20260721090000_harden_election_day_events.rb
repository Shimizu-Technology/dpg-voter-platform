# frozen_string_literal: true

class HardenElectionDayEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :election_events, :training_started_at, :datetime
    add_reference :election_events, :training_started_by_user, foreign_key: { to_table: :users }

    remove_index :election_events, name: "index_election_events_unique_active", if_exists: true
    execute <<~SQL
      CREATE UNIQUE INDEX index_election_events_unique_current
      ON election_events ((1))
      WHERE status IN ('training', 'active')
    SQL
  end

  def down
    remove_index :election_events, name: "index_election_events_unique_current", if_exists: true
    add_index :election_events, :status,
      unique: true,
      where: "status = 'active'",
      name: "index_election_events_unique_active"

    remove_reference :election_events, :training_started_by_user, foreign_key: { to_table: :users }
    remove_column :election_events, :training_started_at
  end
end
