class CreateEventRsvps < ActiveRecord::Migration[8.1]
  def change
    create_table :event_rsvps do |t|
      t.references :event, null: false, foreign_key: true
      t.references :supporter, null: false, foreign_key: true
      t.string :rsvp_status
      t.boolean :attended
      t.datetime :checked_in_at
      t.integer :checked_in_by_id

      t.timestamps
    end
  end
end
