class AddAttributionMethodToSupporters < ActiveRecord::Migration[8.0]
  def up
    add_column :supporters, :attribution_method, :string, default: "public_signup"
    add_index :supporters, :attribution_method

    execute <<~SQL
      UPDATE supporters
      SET attribution_method = CASE
        WHEN leader_code IS NOT NULL AND leader_code <> '' THEN 'qr_self_signup'
        WHEN source = 'bulk_import' THEN 'bulk_import'
        WHEN source = 'staff_entry' THEN 'staff_manual'
        ELSE 'public_signup'
      END
    SQL

    change_column_null :supporters, :attribution_method, false
  end

  def down
    remove_index :supporters, :attribution_method
    remove_column :supporters, :attribution_method
  end
end
