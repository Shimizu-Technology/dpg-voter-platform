class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :name
      t.string :event_type
      t.date :date
      t.time :time
      t.string :location
      t.text :description
      t.references :campaign, null: false, foreign_key: true
      t.references :village, null: true, foreign_key: true
      t.integer :quota
      t.string :status

      t.timestamps
    end
  end
end
