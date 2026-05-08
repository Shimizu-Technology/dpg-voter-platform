class CreateGecImportChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :gec_import_changes do |t|
      t.references :gec_import, null: false, foreign_key: true, index: false
      t.string :change_type, null: false
      t.integer :row_number
      t.string :first_name
      t.string :last_name
      t.string :voter_registration_number
      t.string :village_name
      t.string :previous_village_name
      t.integer :birth_year
      t.date :dob
      t.jsonb :details, null: false, default: {}

      t.timestamps
    end

    add_index :gec_import_changes, [ :gec_import_id, :change_type ]
    add_index :gec_import_changes, :voter_registration_number
  end
end
