class AddVerificationToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :verification_status, :string, default: "unverified", null: false
    add_column :supporters, :verified_by_user_id, :bigint
    add_column :supporters, :verified_at, :datetime

    add_index :supporters, :verification_status
    add_index :supporters, :verified_by_user_id
  end
end
