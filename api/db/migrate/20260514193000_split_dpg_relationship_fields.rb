# frozen_string_literal: true

class SplitDpgRelationshipFields < ActiveRecord::Migration[8.1]
  def up
    add_column :supporters, :support_status, :string, null: false, default: "unknown"
    add_column :supporters, :membership_status, :string, null: false, default: "not_member"
    add_column :supporters, :volunteer_status, :string, null: false, default: "unknown"
    add_index :supporters, :support_status
    add_index :supporters, :membership_status
    add_index :supporters, :volunteer_status

    execute <<~SQL.squish
      UPDATE supporters
      SET
        support_status = CASE
          WHEN contact_classification IN ('supporter', 'member', 'volunteer') THEN 'supporter'
          WHEN contact_classification = 'undecided' THEN 'undecided'
          WHEN contact_classification = 'not_supporting' THEN 'not_supporting'
          ELSE support_status
        END,
        membership_status = CASE
          WHEN contact_classification = 'member' THEN 'member'
          ELSE membership_status
        END,
        volunteer_status = CASE
          WHEN contact_classification = 'volunteer' OR wants_to_volunteer = TRUE THEN 'interested'
          ELSE volunteer_status
        END,
        contact_classification = CASE
          WHEN contact_classification IN ('supporter', 'member', 'volunteer', 'undecided', 'not_supporting') THEN 'active_contact'
          ELSE contact_classification
        END
    SQL
  end

  def down
    remove_index :supporters, :volunteer_status
    remove_index :supporters, :membership_status
    remove_index :supporters, :support_status
    remove_column :supporters, :volunteer_status
    remove_column :supporters, :membership_status
    remove_column :supporters, :support_status
  end
end
