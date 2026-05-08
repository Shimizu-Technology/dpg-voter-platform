class AddShowPaceToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :show_pace, :boolean, default: false, null: false
  end
end
