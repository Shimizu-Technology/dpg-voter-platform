require "test_helper"
require Rails.root.join("db/migrate/20260327133000_add_full_voter_turnout_foundation")

class AddFullVoterTurnoutFoundationTest < ActiveSupport::TestCase
  def setup
    @village = Village.create!(name: "Migration Village")
    @precinct = Precinct.create!(number: "MV-1", village: @village, registered_voters: 100)
    @gec_voter = GecVoter.create!(
      first_name: "Migration",
      last_name: "Voter",
      village: @village,
      village_name: @village.name,
      precinct: @precinct,
      precinct_number: @precinct.number,
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active",
      turnout_status: "not_yet_voted"
    )
  end

  test "backfill_gec_turnout_from_supporters drops legacy war room turnout source" do
    supporter = Supporter.create!(
      first_name: "Migration",
      last_name: "Supporter",
      print_name: "Migration Supporter",
      contact_number: "6715551001",
      village: @village,
      precinct: @precinct,
      source: "staff_entry",
      status: "active"
    )
    supporter.update!(gec_voter: @gec_voter, turnout_status: "voted", turnout_source: "war_room")

    AddFullVoterTurnoutFoundation::MigrationSupporter.reset_column_information
    AddFullVoterTurnoutFoundation::MigrationGecVoter.reset_column_information
    AddFullVoterTurnoutFoundation.new.send(:backfill_gec_turnout_from_supporters!)

    @gec_voter.reload
    assert_equal "voted", @gec_voter.turnout_status
    assert_nil @gec_voter.turnout_source
    assert_nil @gec_voter.turnout_updated_by_user_id
  end

  test "backfill_gec_turnout_from_supporters preserves valid gec turnout sources" do
    supporter = Supporter.create!(
      first_name: "Migration",
      last_name: "Supporter",
      print_name: "Migration Supporter",
      contact_number: "6715551002",
      village: @village,
      precinct: @precinct,
      source: "staff_entry",
      status: "active"
    )
    supporter.update!(gec_voter: @gec_voter, turnout_status: "observed_elsewhere", turnout_source: "data_team")

    AddFullVoterTurnoutFoundation::MigrationSupporter.reset_column_information
    AddFullVoterTurnoutFoundation::MigrationGecVoter.reset_column_information
    AddFullVoterTurnoutFoundation.new.send(:backfill_gec_turnout_from_supporters!)

    @gec_voter.reload
    assert_equal "observed_elsewhere", @gec_voter.turnout_status
    assert_equal "data_team", @gec_voter.turnout_source
  end
end
