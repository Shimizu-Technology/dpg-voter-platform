class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :clerk_id
      t.string :name
      t.string :email
      t.string :phone
      t.string :role
      t.integer :assigned_district_id
      t.integer :assigned_village_id
      t.integer :assigned_block_id

      t.timestamps
    end
  end
end
