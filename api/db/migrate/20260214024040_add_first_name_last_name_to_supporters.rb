# frozen_string_literal: true

class AddFirstNameLastNameToSupporters < ActiveRecord::Migration[8.0]
  def up
    add_column :supporters, :first_name, :string
    add_column :supporters, :last_name, :string

    # Backfill existing print_name data into first_name + last_name.
    # Strategy:
    #   - If contains comma: "Last, First" → last_name="Last", first_name="First"
    #   - Otherwise: "First Last" → first_name="First", last_name="Last"
    #   - Single word: treated as last_name (common for Chamorro single names)
    #   - Three+ words without comma: first word = first_name, rest = last_name
    execute <<~SQL
      UPDATE supporters
      SET
        first_name = CASE
          WHEN print_name LIKE '%,%' THEN TRIM(SPLIT_PART(print_name, ',', 2))
          WHEN print_name LIKE '% %' THEN TRIM(SPLIT_PART(print_name, ' ', 1))
          ELSE NULL
        END,
        last_name = CASE
          WHEN print_name LIKE '%,%' THEN TRIM(SPLIT_PART(print_name, ',', 1))
          WHEN print_name LIKE '% %' THEN TRIM(SUBSTRING(print_name FROM POSITION(' ' IN print_name) + 1))
          ELSE TRIM(print_name)
        END
      WHERE print_name IS NOT NULL;
    SQL

    # Update print_name to be "Last, First" format for consistency
    execute <<~SQL
      UPDATE supporters
      SET print_name = CASE
        WHEN first_name IS NOT NULL AND last_name IS NOT NULL THEN last_name || ', ' || first_name
        WHEN last_name IS NOT NULL THEN last_name
        WHEN first_name IS NOT NULL THEN first_name
        ELSE print_name
      END
      WHERE first_name IS NOT NULL OR last_name IS NOT NULL;
    SQL

    # Add indexes for search and sorting
    add_index :supporters, :last_name
    add_index :supporters, [ :last_name, :first_name ]
  end

  def down
    remove_index :supporters, [ :last_name, :first_name ]
    remove_index :supporters, :last_name
    remove_column :supporters, :first_name
    remove_column :supporters, :last_name
  end
end
