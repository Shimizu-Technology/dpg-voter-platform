class AddVerificationReasonToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :verification_reason, :string
    add_column :supporters, :verification_reason_metadata, :jsonb, null: false, default: {}

    add_index :supporters, :verification_reason
  end
end
