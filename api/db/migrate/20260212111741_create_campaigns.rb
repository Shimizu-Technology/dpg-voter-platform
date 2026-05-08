class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.string :name
      t.integer :election_year
      t.string :election_type
      t.string :status
      t.string :candidate_names
      t.string :party
      t.string :primary_color
      t.string :secondary_color
      t.string :logo_url

      t.timestamps
    end
  end
end
