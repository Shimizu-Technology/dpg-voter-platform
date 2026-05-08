class AddIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :users, :clerk_id, unique: true
    add_index :users, :email, unique: true
    add_index :users, :role
    add_index :supporters, :source
    add_index :supporters, :status
    add_index :supporters, :leader_code
    add_index :supporters, :entered_by_user_id
    add_index :supporters, [ :print_name, :village_id ], name: "index_supporters_on_name_village"
    add_index :events, :event_type
    add_index :events, :status
    add_index :events, :date
    add_index :campaigns, :status
    add_index :villages, :name, unique: true
  end
end
