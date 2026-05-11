# frozen_string_literal: true

class AddContactClassificationToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :contact_classification, :string, null: false, default: "new_intake"
    add_reference :supporters, :classified_by_user, foreign_key: { to_table: :users }
    add_column :supporters, :classified_at, :datetime

    add_index :supporters, :contact_classification
  end
end
