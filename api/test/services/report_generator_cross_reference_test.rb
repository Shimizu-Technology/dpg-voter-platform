require "test_helper"

class ReportGeneratorCrossReferenceTest < ActiveSupport::TestCase
  setup do
    @village = Village.create!(name: "Hagatna")
    @precinct = Precinct.create!(village: @village, number: "1")
    @linked_voter = GecVoter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      birth_year: 1982,
      address: "100 Marine Drive",
      village: @village,
      village_name: @village.name,
      precinct: @precinct,
      precinct_number: @precinct.number,
      voter_registration_number: "GEC-100",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    @unlinked_voter = GecVoter.create!(
      first_name: "Juan",
      last_name: "Santos",
      birth_year: 1975,
      address: "200 Marine Drive",
      village: @village,
      village_name: @village.name,
      precinct: @precinct,
      precinct_number: @precinct.number,
      voter_registration_number: "GEC-200",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    @linked_contact = Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "671-555-0100",
      street_address: @linked_voter.address,
      village: @village,
      precinct: @precinct,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
      status: "active",
      verification_status: "verified"
    )
    @linked_contact.update_columns(gec_voter_id: @linked_voter.id, verification_status: "verified", verification_reason: "matched_current_gec")
    recorder = User.create!(
      clerk_id: "report-recorder-#{SecureRandom.hex(4)}",
      email: "report-recorder-#{SecureRandom.hex(4)}@example.com",
      name: "Report Recorder",
      role: "campaign_admin"
    )
    SupporterContactAttempt.create!(
      supporter: @linked_contact,
      recorded_by_user: recorder,
      channel: "call",
      outcome: "reached",
      note: "Confirmed support by phone.",
      recorded_at: Time.zone.local(2026, 5, 14, 10, 0, 0)
    )
    @unlinked_contact = Supporter.create!(
      first_name: "Ana",
      last_name: "Reyes",
      contact_number: "671-555-0200",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      status: "active",
      verification_status: "unverified",
      verification_reason: "no_gec_match"
    )
    @possible_match = Supporter.create!(
      first_name: "Possible",
      last_name: "Match",
      contact_number: "671-555-0300",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
      membership_status: "member",
      status: "active"
    )
    @possible_match.update_columns(
      verification_status: "flagged",
      verification_reason: "multiple_matches",
      verification_reason_metadata: {
        "confidence" => "high",
        "match_type" => "name_year_village",
        "match_count" => 2,
        "gec_village_name" => @village.name
      }
    )
  end

  test "linked DPG contact report shows contacts with GEC links" do
    preview = ReportGenerator.new(report_type: "dpg_contacts_linked_to_gec").preview

    assert_equal 1, preview[:total_count]
    assert_equal "Maria", preview[:rows].first[1]
    assert_includes preview[:columns], "GEC Reg #"
    assert_includes preview[:columns], "Last Contact Outcome"
    assert_includes preview[:rows].first, @linked_voter.voter_registration_number
    assert_includes preview[:rows].first, "Reached"
    assert_includes preview[:rows].first, "Confirmed support by phone."
  end

  test "unlinked DPG contact report includes contacts without GEC links" do
    preview = ReportGenerator.new(report_type: "dpg_contacts_unlinked_from_gec").preview

    assert_equal 2, preview[:total_count]
    names = preview[:rows].map { |row| row[1] }
    assert_includes names, @unlinked_contact.first_name
    assert_includes names, @possible_match.first_name
  end

  test "GEC voters not in DPG report excludes linked voters" do
    preview = ReportGenerator.new(report_type: "gec_voters_not_in_dpg").preview

    assert_equal 1, preview[:total_count]
    assert_equal @unlinked_voter.voter_registration_number, preview[:rows].first[7]
  end

  test "possible GEC matches report exposes manual review notes" do
    preview = ReportGenerator.new(report_type: "possible_gec_matches").preview

    assert_equal 1, preview[:total_count]
    assert_equal @possible_match.first_name, preview[:rows].first[1]
    assert_match "Candidates: 2", preview[:rows].first.last
  end
end
