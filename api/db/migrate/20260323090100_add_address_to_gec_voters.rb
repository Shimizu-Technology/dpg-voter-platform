class AddAddressToGecVoters < ActiveRecord::Migration[8.1]
  def change
    add_column :gec_voters, :address, :text
  end
end
