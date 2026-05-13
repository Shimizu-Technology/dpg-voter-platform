# frozen_string_literal: true

class AddFileS3KeyToGecImportUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :gec_import_uploads, :file_s3_key, :string
    change_column_null :gec_import_uploads, :file_data, true
    add_index :gec_import_uploads, :file_s3_key
  end
end
