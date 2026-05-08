class CreatePollReports < ActiveRecord::Migration[8.1]
  def change
    create_table :poll_reports do |t|
      t.references :precinct, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :voter_count, null: false
      t.string :report_type, null: false, default: "turnout_update"
      t.text :notes
      t.datetime :reported_at, null: false

      t.timestamps
    end

    add_index :poll_reports, [ :precinct_id, :reported_at ]
  end
end
