class AddSocialMediaLinksToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :instagram_url, :string
    add_column :campaigns, :facebook_url, :string
    add_column :campaigns, :tiktok_url, :string
    add_column :campaigns, :twitter_url, :string
  end
end
