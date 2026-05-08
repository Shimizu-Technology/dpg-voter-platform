class AddNormalizedPhoneToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :normalized_phone, :string

    # Index for exact match lookups during duplicate detection
    add_index :supporters, :normalized_phone, name: "index_supporters_on_normalized_phone"

    # Expression index for name+village duplicate matching (LOWER/TRIM used in queries)
    add_index :supporters, "village_id, LOWER(TRIM(first_name)), LOWER(TRIM(last_name))",
              name: "index_supporters_on_village_lower_first_last_name"

    # Expression index for email duplicate matching (LOWER used in queries)
    add_index :supporters, "LOWER(email)",
              name: "index_supporters_on_lower_email",
              where: "email IS NOT NULL"

    # Backfill normalized phones
    reversible do |dir|
      dir.up do
        # Strip non-digits, normalize Guam country code (1671 -> 671),
        # and set NULL (not empty string) for non-numeric values
        execute <<-SQL
          UPDATE supporters
          SET normalized_phone = CASE
            WHEN REGEXP_REPLACE(contact_number, '[^0-9]', '', 'g') = '' THEN NULL
            WHEN REGEXP_REPLACE(contact_number, '[^0-9]', '', 'g') ~ '^1671' AND LENGTH(REGEXP_REPLACE(contact_number, '[^0-9]', '', 'g')) >= 11
            THEN SUBSTRING(REGEXP_REPLACE(contact_number, '[^0-9]', '', 'g') FROM 2)
            ELSE REGEXP_REPLACE(contact_number, '[^0-9]', '', 'g')
          END
          WHERE contact_number IS NOT NULL
        SQL
      end
    end
  end
end
