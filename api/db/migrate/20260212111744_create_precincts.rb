class CreatePrecincts < ActiveRecord::Migration[8.1]
  def change
    create_table :precincts do |t|
      t.string :number
      t.string :alpha_range
      t.references :village, null: false, foreign_key: true
      t.integer :registered_voters
      t.string :polling_site

      t.timestamps
    end
  end
end
