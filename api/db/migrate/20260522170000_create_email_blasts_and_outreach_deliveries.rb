# frozen_string_literal: true

class CreateEmailBlastsAndOutreachDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :email_blasts do |t|
      t.string :status, null: false, default: "pending"
      t.string :subject, null: false
      t.text :body
      t.jsonb :filters, default: {}, null: false
      t.references :initiated_by_user, foreign_key: { to_table: :users }, null: false
      t.integer :total_recipients, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :error_log, default: [], null: false
      t.timestamps
    end

    add_index :email_blasts, :status
    add_index :email_blasts, :created_at

    create_table :outreach_deliveries do |t|
      t.string :channel, null: false
      t.references :sms_blast, foreign_key: true, null: true
      t.references :email_blast, foreign_key: true, null: true
      t.references :supporter, foreign_key: true, null: false
      t.references :resend_of, foreign_key: { to_table: :outreach_deliveries }, null: true
      t.string :recipient, null: false
      t.string :provider, null: false
      t.string :provider_message_id
      t.string :status, null: false, default: "queued"
      t.string :provider_status_code
      t.string :provider_status_text
      t.string :provider_error_code
      t.datetime :last_event_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :outreach_deliveries, :channel
    add_index :outreach_deliveries, :status
    add_index :outreach_deliveries, :provider_message_id
    add_index :outreach_deliveries, [ :sms_blast_id, :status ]
    add_index :outreach_deliveries, [ :email_blast_id, :status ]
  end
end
