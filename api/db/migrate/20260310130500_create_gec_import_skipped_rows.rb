class CreateGecImportSkippedRows < ActiveRecord::Migration[8.1]
  def change
    create_table :gec_import_skipped_rows do |t|
      t.references :gec_import, null: false, foreign_key: true, index: false
      t.references :resolved_by_user, foreign_key: { to_table: :users }
      t.references :resolved_gec_voter, foreign_key: { to_table: :gec_voters }
      t.integer :row_number, null: false
      t.string :message, null: false
      t.string :source_name
      t.string :first_name
      t.string :last_name
      t.string :voter_registration_number
      t.string :village_name
      t.integer :birth_year
      t.date :dob
      t.jsonb :raw_values, null: false, default: []
      t.string :resolution_status, null: false, default: "pending"
      t.string :resolution_action
      t.jsonb :corrected_values, null: false, default: {}
      t.jsonb :resolution_details, null: false, default: {}
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :gec_import_skipped_rows, [ :gec_import_id, :resolution_status ], name: "index_gec_import_skipped_rows_on_import_and_status"
    add_index :gec_import_skipped_rows, [ :gec_import_id, :row_number ], unique: true, name: "index_gec_import_skipped_rows_on_import_and_row"
  end
end
