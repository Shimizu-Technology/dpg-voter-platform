class CreateSmsBlasts < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_blasts do |t|
      t.string :status
      t.integer :total_recipients
      t.integer :sent_count
      t.integer :failed_count
      t.text :message
      t.jsonb :filters
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :error_log
      t.integer :initiated_by_user_id

      t.timestamps
    end

    add_index :sms_blasts, :status
    add_index :sms_blasts, :initiated_by_user_id
  end
end
