class AddSubmittedVillageToSupporters < ActiveRecord::Migration[8.1]
  def up
    add_reference :supporters, :submitted_village, foreign_key: { to_table: :villages }, null: true

    execute <<~SQL
      UPDATE supporters
      SET submitted_village_id = COALESCE(referred_from_village_id, village_id)
      WHERE submitted_village_id IS NULL
    SQL
  end

  def down
    remove_reference :supporters, :submitted_village, foreign_key: { to_table: :villages }
  end
end
