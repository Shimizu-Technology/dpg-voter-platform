require "test_helper"

class ElectionTurnoutUpdateServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(clerk_id: "turnout-service-user", email: "turnout-service-user@example.com", name: "Turnout Service User", role: "campaign_admin")
    @village = Village.create!(name: "Service Village")
    @precinct = Precinct.create!(village: @village, number: "1")
    @gec_import = GecImport.create!(filename: "service-gec.xlsx", gec_list_date: Date.new(2026, 5, 1), status: "completed")
    @event = ElectionEvent.create!(name: "Service Election", election_type: "primary", election_date: Date.new(2026, 8, 1), gec_import: @gec_import)
    @voter = GecVoter.create!(
      first_name: "Service",
      last_name: "Voter",
      birth_year: 1988,
      village: @village,
      village_name: @village.name,
      precinct: @precinct,
      precinct_number: @precinct.number,
      gec_list_date: @gec_import.gec_list_date,
      imported_at: Time.current
    )
  end

  test "returns failure and rolls back election turnout record when current turnout sync fails" do
    @voter.update_column(:status, "invalid_status")

    result = ElectionTurnoutUpdateService.new(
      election_event: @event,
      gec_voter: @voter,
      actor_user: @user,
      turnout_status: "voted",
      source: "admin_override"
    ).call

    assert_not result.success?
    assert_includes result.errors, "Status is not included in the list"
    assert_nil ElectionTurnoutRecord.find_by(election_event: @event, gec_voter: @voter)
    assert_equal "not_yet_voted", @voter.reload.turnout_status
  end
end
