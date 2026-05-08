class AddWelcomeSmsTemplateToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :welcome_sms_template, :text
  end
end
