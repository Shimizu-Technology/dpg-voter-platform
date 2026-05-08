class CreateGecImportUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :gec_import_uploads do |t|
      t.references :gec_import, null: false, foreign_key: true, index: { unique: true }
      t.string :filename, null: false
      t.string :content_type
      t.binary :file_data, null: false

      t.timestamps
    end
  end
end
