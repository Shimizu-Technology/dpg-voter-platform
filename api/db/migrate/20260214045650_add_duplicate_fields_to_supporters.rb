class AddDuplicateFieldsToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :potential_duplicate, :boolean, default: false, null: false
    add_column :supporters, :duplicate_of_id, :bigint
    add_column :supporters, :duplicate_checked_at, :datetime
    add_column :supporters, :duplicate_notes, :text

    add_index :supporters, :potential_duplicate
    add_index :supporters, :duplicate_of_id
    add_foreign_key :supporters, :supporters, column: :duplicate_of_id
  end
end
