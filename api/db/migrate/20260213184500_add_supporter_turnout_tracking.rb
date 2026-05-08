class AddSupporterTurnoutTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :turnout_status, :string, null: false, default: "unknown"
    add_column :supporters, :turnout_updated_at, :datetime
    add_reference :supporters, :turnout_updated_by_user, foreign_key: { to_table: :users }, index: true
    add_column :supporters, :turnout_source, :string
    add_column :supporters, :turnout_note, :text

    add_index :supporters, :turnout_status
    add_index :supporters, [ :precinct_id, :turnout_status ], name: "index_supporters_on_precinct_id_and_turnout_status"

    create_table :supporter_contact_attempts do |t|
      t.references :supporter, null: false, foreign_key: true
      t.references :recorded_by_user, null: false, foreign_key: { to_table: :users }
      t.string :outcome, null: false
      t.string :channel, null: false
      t.datetime :recorded_at, null: false
      t.text :note

      t.timestamps
    end

    add_index :supporter_contact_attempts, [ :supporter_id, :recorded_at ], name: "index_contact_attempts_on_supporter_and_recorded_at"
    add_index :supporter_contact_attempts, :outcome
  end
end
