class SetDefaultSocialLinks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE campaigns
      SET instagram_url = COALESCE(instagram_url, 'https://www.instagram.com/democraticpartyofguam'),
          facebook_url = COALESCE(facebook_url, 'https://www.facebook.com/democraticpartyofguam'),
          tiktok_url = COALESCE(tiktok_url, '')
    SQL
  end

  def down
    # No-op: links can be edited via admin UI
  end
end
