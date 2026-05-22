# frozen_string_literal: true

class AddUniqueCampaignCycleNameIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :campaign_cycles, :name, unique: true, name: "index_campaign_cycles_on_unique_name"
  end
end
