class CreateDuplicatePairDismissals < ActiveRecord::Migration[8.0]
  def change
    create_table :duplicate_pair_dismissals do |t|
      t.references :supporter, null: false, foreign_key: { to_table: :supporters }
      t.references :dismissed_supporter, null: false, foreign_key: { to_table: :supporters }
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.text :note

      t.timestamps
    end

    add_index :duplicate_pair_dismissals,
      [ :supporter_id, :dismissed_supporter_id ],
      unique: true,
      name: "index_duplicate_pair_dismissals_on_pair"

    add_check_constraint :duplicate_pair_dismissals,
      "supporter_id < dismissed_supporter_id",
      name: "duplicate_pair_dismissals_ordered_pair"
  end
end
