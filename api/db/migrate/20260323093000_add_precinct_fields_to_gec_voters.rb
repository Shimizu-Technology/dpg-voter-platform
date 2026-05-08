class AddPrecinctFieldsToGecVoters < ActiveRecord::Migration[8.1]
  def change
    add_reference :gec_voters, :precinct, foreign_key: true, null: true
    add_column :gec_voters, :precinct_number, :string
    add_index :gec_voters, [ :village_id, :precinct_number ]
  end
end
