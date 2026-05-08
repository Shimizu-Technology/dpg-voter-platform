class BackfillThankYouReminderDefaults < ActiveRecord::Migration[8.1]
  class Campaign < ApplicationRecord
    self.table_name = "campaigns"
  end

  DEFAULT_SHARE_PROMPT = <<~TEXT.squish.freeze
    Know other the Democratic Party of Guam supporters? Please share this link with them so we can get
    their names included and keep them connected with the campaign.
  TEXT

  PRIMARY_ELECTION_DATE = Date.new(2026, 8, 1)
  GENERAL_ELECTION_DATE = Date.new(2026, 11, 3)

  def up
    Campaign.where(thank_you_share_prompt: [ nil, "" ]).update_all(thank_you_share_prompt: DEFAULT_SHARE_PROMPT)
    Campaign.where(primary_election_date: nil).update_all(primary_election_date: PRIMARY_ELECTION_DATE)
    Campaign.where(general_election_date: nil).update_all(general_election_date: GENERAL_ELECTION_DATE)
  end

  def down
    # This backfill only seeds defaults. Leave existing data untouched on rollback
    # so an isolated migration rollback cannot clear values someone later edited.
  end
end
