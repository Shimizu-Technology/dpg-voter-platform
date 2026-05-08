class AddUnassignedVillage < ActiveRecord::Migration[8.1]
  def up
    # Create the "Unassigned" village for GMF/military/off-island voters
    # who don't map to any standard Guam village
    Village.find_or_create_by!(name: "Unassigned") do |v|
      v.region = "Other"
      v.population = 0
    end
  end

  def down
    Village.find_by(name: "Unassigned")&.destroy
  end
end
