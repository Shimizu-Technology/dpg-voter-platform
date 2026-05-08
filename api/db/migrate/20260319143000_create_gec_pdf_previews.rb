class CreateGecPdfPreviews < ActiveRecord::Migration[8.1]
  def change
    create_table :gec_pdf_previews do |t|
      t.string :preview_request_id, null: false
      t.references :uploaded_by_user, null: false, foreign_key: { to_table: :users }
      t.string :filename, null: false
      t.string :content_type
      t.string :status, null: false, default: "pending"
      t.binary :file_data
      t.jsonb :result_data, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :gec_pdf_previews, :preview_request_id, unique: true
    add_index :gec_pdf_previews, [ :uploaded_by_user_id, :status ]
  end
end
