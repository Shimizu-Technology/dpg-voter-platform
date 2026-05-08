class CreateVillages < ActiveRecord::Migration[8.1]
  def change
    create_table :villages do |t|
      t.string :name
      t.references :district, null: true, foreign_key: true
      t.integer :registered_voters
      t.integer :precinct_count
      t.integer :population
      t.string :region

      t.timestamps
    end
  end
end
