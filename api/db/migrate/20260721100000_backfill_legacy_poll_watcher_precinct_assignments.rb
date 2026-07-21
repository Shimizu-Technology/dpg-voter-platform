# frozen_string_literal: true

class BackfillLegacyPollWatcherPrecinctAssignments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO poll_watcher_precinct_assignments
        (user_id, precinct_id, assigned_by_user_id, assigned_at, created_at, updated_at)
      SELECT
        users.id,
        precincts.id,
        NULL,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      INNER JOIN precincts
        ON precincts.village_id = users.assigned_village_id
        AND precincts.active = TRUE
      WHERE users.role = 'poll_watcher'
        AND users.assigned_village_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM poll_watcher_precinct_assignments existing_assignments
          WHERE existing_assignments.user_id = users.id
        )
      ON CONFLICT (user_id, precinct_id) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Legacy village access was converted to explicit precinct assignments and cannot be distinguished safely from later assignments"
  end
end
