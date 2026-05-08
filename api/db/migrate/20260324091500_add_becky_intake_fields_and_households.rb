class AddVoterHelpIntakeFieldsAndHouseholds < ActiveRecord::Migration[8.1]
  def up
    create_table :household_groups do |t|
      t.bigint :village_id, null: false
      t.string :shared_contact_number
      t.string :shared_email
      t.string :street_address
      t.timestamps
    end

    add_index :household_groups, :village_id
    add_index :household_groups, :shared_contact_number
    add_foreign_key :household_groups, :villages

    change_table :supporters, bulk: true do |t|
      t.string :registered_voter_status, default: "not_sure", null: false
      t.text :registered_voter_location_note
      t.boolean :wants_to_volunteer, default: false, null: false
      t.boolean :needs_absentee_ballot_help, default: false, null: false
      t.boolean :needs_homebound_voting_help, default: false, null: false
      t.boolean :needs_voter_registration_help, default: false, null: false
      t.boolean :needs_election_day_ride, default: false, null: false
      t.string :referred_by_name
      t.bigint :household_group_id
      t.boolean :household_primary, default: false, null: false
    end

    add_index :supporters, :registered_voter_status
    add_index :supporters, :needs_voter_registration_help
    add_index :supporters, :household_group_id
    add_foreign_key :supporters, :household_groups

    execute <<~SQL.squish
      UPDATE supporters
      SET registered_voter_status = CASE
        WHEN self_reported_registered_voter = TRUE THEN 'yes'
        WHEN self_reported_registered_voter = FALSE THEN 'no'
        ELSE 'not_sure'
      END
    SQL
  end

  def down
    remove_foreign_key :supporters, :household_groups
    remove_index :supporters, :household_group_id
    remove_index :supporters, :needs_voter_registration_help
    remove_index :supporters, :registered_voter_status

    change_table :supporters, bulk: true do |t|
      t.remove :registered_voter_status
      t.remove :registered_voter_location_note
      t.remove :wants_to_volunteer
      t.remove :needs_absentee_ballot_help
      t.remove :needs_homebound_voting_help
      t.remove :needs_voter_registration_help
      t.remove :needs_election_day_ride
      t.remove :referred_by_name
      t.remove :household_group_id
      t.remove :household_primary
    end

    remove_foreign_key :household_groups, :villages
    remove_index :household_groups, :shared_contact_number
    remove_index :household_groups, :village_id
    drop_table :household_groups
  end
end
