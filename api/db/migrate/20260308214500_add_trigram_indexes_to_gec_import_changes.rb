class AddTrigramIndexesToGecImportChanges < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE INDEX idx_gec_import_changes_first_name_trgm
      ON gec_import_changes
      USING gin (LOWER(first_name) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX idx_gec_import_changes_last_name_trgm
      ON gec_import_changes
      USING gin (LOWER(last_name) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX idx_gec_import_changes_village_name_trgm
      ON gec_import_changes
      USING gin (LOWER(village_name) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX idx_gec_import_changes_prev_village_trgm
      ON gec_import_changes
      USING gin (LOWER(previous_village_name) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX idx_gec_import_changes_vrn_trgm
      ON gec_import_changes
      USING gin (LOWER(voter_registration_number) gin_trgm_ops);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_gec_import_changes_first_name_trgm"
    execute "DROP INDEX IF EXISTS idx_gec_import_changes_last_name_trgm"
    execute "DROP INDEX IF EXISTS idx_gec_import_changes_village_name_trgm"
    execute "DROP INDEX IF EXISTS idx_gec_import_changes_prev_village_trgm"
    execute "DROP INDEX IF EXISTS idx_gec_import_changes_vrn_trgm"
  end
end
