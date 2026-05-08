class CreateGecVoters < ActiveRecord::Migration[8.1]
  def change
    create_table :gec_voters do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.date :dob
      t.string :village_name, null: false
      t.references :village, foreign_key: true
      t.string :voter_registration_number
      t.string :status, default: "active", null: false
      t.boolean :dob_ambiguous, default: false, null: false
      t.date :gec_list_date, null: false
      t.datetime :imported_at, null: false

      t.timestamps
    end

    add_index :gec_voters, [ :last_name, :first_name, :dob ], name: "index_gec_voters_on_name_and_dob"
    add_index :gec_voters, :village_name
    add_index :gec_voters, :voter_registration_number
    add_index :gec_voters, :gec_list_date
    add_index :gec_voters, [ :village_id, :last_name ], name: "index_gec_voters_on_village_and_last_name"

    create_table :gec_imports do |t|
      t.date :gec_list_date, null: false
      t.string :filename, null: false
      t.integer :total_records, default: 0, null: false
      t.integer :new_records, default: 0, null: false
      t.integer :updated_records, default: 0, null: false
      t.integer :removed_records, default: 0, null: false
      t.integer :ambiguous_dob_count, default: 0, null: false
      t.string :status, default: "pending", null: false
      t.references :uploaded_by_user, foreign_key: { to_table: :users }
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :gec_imports, :gec_list_date
  end
end
