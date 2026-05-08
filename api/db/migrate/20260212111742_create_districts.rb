class CreateDistricts < ActiveRecord::Migration[8.1]
  def change
    create_table :districts do |t|
      t.string :name
      t.integer :number
      t.references :campaign, null: false, foreign_key: true
      t.integer :coordinator_id
      t.text :description

      t.timestamps
    end
  end
end
