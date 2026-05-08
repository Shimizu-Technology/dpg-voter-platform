class AddGecRefreshFields < ActiveRecord::Migration[8.0]
  def change
    # GecImport: track import type and change stats
    add_column :gec_imports, :import_type, :string, default: "full_list", null: false
    add_column :gec_imports, :transferred_records, :integer, default: 0, null: false
    add_column :gec_imports, :re_vetted_count, :integer, default: 0, null: false

    # GecVoter: track village transfers and removal info
    add_column :gec_voters, :previous_village_name, :string
    add_column :gec_voters, :removed_at, :datetime
    add_column :gec_voters, :removal_detected_by_import_id, :bigint

    add_index :gec_voters, :status
    add_index :gec_voters, :removed_at, where: "removed_at IS NOT NULL"
  end
end
