class AddActiveToPrecincts < ActiveRecord::Migration[8.1]
  def change
    add_column :precincts, :active, :boolean, default: true, null: false
    add_index :precincts, :active
  end
end
