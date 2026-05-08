class AddMiddleNamesToSupportersAndGecRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :supporters, :middle_name, :string
    add_column :gec_voters, :middle_name, :string
    add_column :gec_import_changes, :middle_name, :string
    add_column :gec_import_skipped_rows, :middle_name, :string
  end
end
