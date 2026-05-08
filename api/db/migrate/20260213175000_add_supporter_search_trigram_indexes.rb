class AddSupporterSearchTrigramIndexes < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_supporters_on_lower_print_name_trgm
      ON supporters
      USING gin (LOWER(print_name) gin_trgm_ops);
    SQL

    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_supporters_on_contact_number_trgm
      ON supporters
      USING gin (contact_number gin_trgm_ops);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_supporters_on_lower_print_name_trgm;"
    execute "DROP INDEX IF EXISTS index_supporters_on_contact_number_trgm;"
  end
end
