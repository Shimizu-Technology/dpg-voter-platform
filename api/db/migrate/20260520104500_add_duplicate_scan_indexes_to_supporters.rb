# frozen_string_literal: true

class AddDuplicateScanIndexesToSupporters < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :supporters,
              "dob, lower(TRIM(BOTH FROM first_name)), lower(TRIM(BOTH FROM last_name))",
              name: "index_supporters_on_dob_and_lower_trimmed_names",
              where: "dob IS NOT NULL AND first_name IS NOT NULL AND last_name IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :supporters,
              "lower(TRIM(BOTH FROM street_address)), lower(TRIM(BOTH FROM first_name)), lower(TRIM(BOTH FROM last_name))",
              name: "index_supporters_on_lower_trimmed_address_and_names",
              where: "street_address IS NOT NULL AND street_address <> '' AND first_name IS NOT NULL AND last_name IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
