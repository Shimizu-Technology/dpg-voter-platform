class AddOptInFieldsToSupporters < ActiveRecord::Migration[8.1]
  def change
    add_column :supporters, :opt_in_email, :boolean, default: false, null: false
    add_column :supporters, :opt_in_text, :boolean, default: false, null: false
  end
end
