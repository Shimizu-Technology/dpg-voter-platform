class AddSupporterPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :supporters, [ :status, :village_id ], if_not_exists: true
    add_index :supporters, [ :status, :village_id, :motorcade_available ], if_not_exists: true
  end
end
