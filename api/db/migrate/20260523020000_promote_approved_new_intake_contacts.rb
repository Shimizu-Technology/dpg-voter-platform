# frozen_string_literal: true

class PromoteApprovedNewIntakeContacts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE supporters
      SET contact_classification = 'active_contact',
          classified_at = COALESCE(classified_at, reviewed_at, updated_at, NOW()),
          updated_at = NOW()
      WHERE contact_classification = 'new_intake'
        AND review_status = 'approved'
        AND status = 'active'
    SQL
  end

  def down
    # No-op: this repairs inconsistent reviewed intake records. Reverting would
    # hide approved contacts from both Pending Intake and Reviewed Contacts.
  end
end
