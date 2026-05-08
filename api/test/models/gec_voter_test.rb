require "test_helper"

class GecVoterTest < ActiveSupport::TestCase
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
  end

  test "find_matches_for_supporters resolves fuzzy name matches without SQL errors" do
    GecVoter.create!(
      first_name: "John",
      last_name: "Smith",
      birth_year: 1985,
      village_name: @village.name,
      voter_registration_number: "VRFUZZY1",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )

    supporter = Supporter.create!(
      first_name: "John",
      last_name: "Smit",
      print_name: "John Smit",
      dob: Date.new(1985, 3, 15),
      contact_number: "6715559123",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: nil,
      verification_reason_metadata: {}
    )

    matches = GecVoter.find_matches_for_supporters([ supporter ])

    assert_equal 1, matches[supporter.id].size
    assert_equal :fuzzy_name_year, matches[supporter.id].first[:match_type]
    assert_equal :medium, matches[supporter.id].first[:confidence]
  end
end
