class AddRawFileFieldsToGecImports < ActiveRecord::Migration[8.1]
  def change
    add_column :gec_imports, :raw_file_s3_key, :string
    add_column :gec_imports, :raw_filename, :string
    add_column :gec_imports, :raw_content_type, :string
  end
end
