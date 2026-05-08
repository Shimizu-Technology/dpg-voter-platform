class AddBirthYearToGecVoters < ActiveRecord::Migration[8.1]
  def up
    add_column :gec_voters, :birth_year, :integer
    add_index :gec_voters,
              "lower((first_name)::text), lower((last_name)::text), birth_year",
              name: "index_gec_voters_on_lower_names_and_birth_year"
    add_index :gec_voters,
              [ :last_name, :first_name, :birth_year ],
              name: "index_gec_voters_on_name_and_birth_year"

    # Backfill from existing dob records
    execute <<~SQL
      UPDATE gec_voters
      SET birth_year = EXTRACT(YEAR FROM dob)::integer
      WHERE dob IS NOT NULL AND birth_year IS NULL
    SQL
  end

  def down
    remove_index :gec_voters, name: "index_gec_voters_on_lower_names_and_birth_year"
    remove_index :gec_voters, name: "index_gec_voters_on_name_and_birth_year"
    remove_column :gec_voters, :birth_year
  end
end
