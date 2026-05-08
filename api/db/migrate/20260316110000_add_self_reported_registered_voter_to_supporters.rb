class AddSelfReportedRegisteredVoterToSupporters < ActiveRecord::Migration[8.0]
  def up
    add_column :supporters, :self_reported_registered_voter, :boolean
    add_index :supporters, :self_reported_registered_voter

    execute <<~SQL.squish
      UPDATE supporters
      SET self_reported_registered_voter = registered_voter
      WHERE self_reported_registered_voter IS NULL
    SQL
  end

  def down
    remove_index :supporters, :self_reported_registered_voter
    remove_column :supporters, :self_reported_registered_voter
  end
end
