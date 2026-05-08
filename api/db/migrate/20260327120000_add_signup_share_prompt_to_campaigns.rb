class AddSignupSharePromptToCampaigns < ActiveRecord::Migration[8.1]
  class Campaign < ApplicationRecord
    self.table_name = "campaigns"
  end

  DEFAULT_SIGNUP_SHARE_PROMPT = <<~TEXT.squish.freeze
    Know other the Democratic Party of Guam supporters? Finish your signup, then share this form with them too.
  TEXT

  def up
    add_column :campaigns, :signup_share_prompt, :text

    Campaign.where(signup_share_prompt: [ nil, "" ]).update_all(signup_share_prompt: DEFAULT_SIGNUP_SHARE_PROMPT)
  end

  def down
    remove_column :campaigns, :signup_share_prompt
  end
end
