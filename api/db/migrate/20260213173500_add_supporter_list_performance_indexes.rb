class AddSupporterListPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :supporters, :created_at, if_not_exists: true
    add_index :supporters, [ :village_id, :created_at ], if_not_exists: true
    add_index :supporters, [ :precinct_id, :created_at ], if_not_exists: true
  end
end
