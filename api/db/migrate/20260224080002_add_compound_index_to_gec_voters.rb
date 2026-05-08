class AddCompoundIndexToGecVoters < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Compound index for the primary lookup pattern in GecVoter.find_matches:
    # WHERE LOWER(first_name) = ? AND LOWER(last_name) = ? AND dob = ?
    add_index :gec_voters, "LOWER(first_name), LOWER(last_name), dob",
              name: "index_gec_voters_on_lower_names_and_dob",
              algorithm: :concurrently,
              if_not_exists: true

    # Compound index for name + village lookups
    add_index :gec_voters, "LOWER(first_name), LOWER(last_name), LOWER(village_name)",
              name: "index_gec_voters_on_lower_names_and_village",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
