class RemoveRedundantGecImportChangesImportIdIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :gec_import_changes, name: "index_gec_import_changes_on_gec_import_id", if_exists: true
  end
end
