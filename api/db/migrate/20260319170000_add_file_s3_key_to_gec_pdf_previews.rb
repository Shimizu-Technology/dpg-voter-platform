class AddFileS3KeyToGecPdfPreviews < ActiveRecord::Migration[8.1]
  def change
    add_column :gec_pdf_previews, :file_s3_key, :string
    add_index :gec_pdf_previews, :file_s3_key
  end
end
