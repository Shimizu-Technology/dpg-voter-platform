class CreateBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :blocks do |t|
      t.string :name
      t.references :village, null: false, foreign_key: true
      t.integer :leader_id

      t.timestamps
    end
  end
end
