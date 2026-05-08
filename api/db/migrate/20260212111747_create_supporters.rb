class CreateSupporters < ActiveRecord::Migration[8.1]
  def change
    create_table :supporters do |t|
      t.string :print_name
      t.string :contact_number
      t.date :dob
      t.string :email
      t.string :street_address
      t.references :village, null: false, foreign_key: true
      t.references :precinct, null: true, foreign_key: true
      t.references :block, null: true, foreign_key: true
      t.boolean :registered_voter
      t.boolean :yard_sign
      t.boolean :motorcade_available
      t.string :source
      t.integer :entered_by_user_id
      t.integer :referred_from_village_id
      t.string :status
      t.string :leader_code

      t.timestamps
    end
  end
end
