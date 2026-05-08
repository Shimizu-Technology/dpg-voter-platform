class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.bigint :actor_user_id
      t.string :action, null: false
      t.jsonb :changed_data, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :audit_logs, [ :auditable_type, :auditable_id, :created_at ], name: "index_audit_logs_on_auditable_and_created_at"
    add_index :audit_logs, :actor_user_id
    add_index :audit_logs, :action
    add_foreign_key :audit_logs, :users, column: :actor_user_id
  end
end
