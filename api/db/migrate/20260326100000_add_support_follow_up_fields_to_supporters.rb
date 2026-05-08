class AddSupportFollowUpFieldsToSupporters < ActiveRecord::Migration[8.1]
  def change
    change_table :supporters, bulk: true do |t|
      t.string :support_follow_up_status
      t.text :support_follow_up_notes
      t.datetime :support_follow_up_date
    end

    add_index :supporters, :support_follow_up_status
  end
end
