class AddElectionDayReadinessFoundation < ActiveRecord::Migration[8.1]
  def change
    change_table :gec_imports, bulk: true do |t|
      t.boolean :active_election_day, null: false, default: false
      t.datetime :activated_for_election_at
      t.bigint :activated_for_election_by_user_id
    end

    add_index :gec_imports, :active_election_day, unique: true, where: "active_election_day", name: "index_gec_imports_on_active_election_day"
    add_foreign_key :gec_imports, :users, column: :activated_for_election_by_user_id

    create_table :poll_watcher_precinct_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :precinct, null: false, foreign_key: true
      t.references :assigned_by_user, foreign_key: { to_table: :users }
      t.datetime :assigned_at, null: false
      t.timestamps

      t.index [ :user_id, :precinct_id ], unique: true, name: "index_poll_watcher_assignments_on_user_and_precinct"
    end
  end
end
