class AddIntakeStatusToSupporters < ActiveRecord::Migration[8.0]
  def up
    add_column :supporters, :intake_status, :string, null: false, default: "accepted"
    add_index :supporters, :intake_status

    execute <<~SQL
      UPDATE supporters
      SET intake_status = 'pending_public_review'
      WHERE source IN ('public_signup', 'qr_signup')
    SQL

    execute <<~SQL
      UPDATE supporters
      SET source = 'public_signup',
          intake_status = 'accepted'
      WHERE source = 'staff_entry'
        AND attribution_method = 'public_signup'
    SQL

    execute <<~SQL
      UPDATE supporters
      SET source = 'qr_signup',
          intake_status = 'accepted'
      WHERE source = 'staff_entry'
        AND attribution_method = 'qr_self_signup'
    SQL
  end

  def down
    remove_index :supporters, :intake_status
    remove_column :supporters, :intake_status
  end
end
