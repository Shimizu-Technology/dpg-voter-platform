class AddOriginalFileFieldsToGecImports < ActiveRecord::Migration[8.1]
  def change
    add_column :gec_imports, :original_file_s3_key, :string
    add_column :gec_imports, :original_filename, :string
    add_column :gec_imports, :original_content_type, :string
  end
end
