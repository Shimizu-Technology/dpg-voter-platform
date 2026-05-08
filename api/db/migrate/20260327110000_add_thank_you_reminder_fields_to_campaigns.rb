class AddThankYouReminderFieldsToCampaigns < ActiveRecord::Migration[8.1]
  def change
    change_table :campaigns, bulk: true do |t|
      t.text :thank_you_share_prompt
      t.date :primary_election_date
      t.date :general_election_date
    end
  end
end
