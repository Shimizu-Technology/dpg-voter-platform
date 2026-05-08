# frozen_string_literal: true

class RemoveRegisteredVotersFromVillages < ActiveRecord::Migration[8.0]
  def up
    remove_column :villages, :registered_voters
    remove_column :villages, :precinct_count
  end

  def down
    add_column :villages, :registered_voters, :integer
    add_column :villages, :precinct_count, :integer

    # Backfill from precincts
    execute <<~SQL
      UPDATE villages
      SET registered_voters = (
        SELECT COALESCE(SUM(precincts.registered_voters), 0)
        FROM precincts
        WHERE precincts.village_id = villages.id
      ),
      precinct_count = (
        SELECT COUNT(*)
        FROM precincts
        WHERE precincts.village_id = villages.id
      )
    SQL
  end
end
