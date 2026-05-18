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
    assert_equal @linked_contact.id, preview[:rows].first[0]
    assert_equal "Maria", preview[:rows].first[2]
    assert_includes preview[:columns], "GEC Reg #"
    assert_includes preview[:columns], "Last Contact Outcome"
    assert_includes preview[:rows].first, @linked_voter.voter_registration_number
    assert_includes preview[:rows].first, "Reached"
    assert_includes preview[:rows].first, "Confirmed support by phone."
  end

  test "unlinked DPG contact report includes contacts without GEC links" do
    preview = ReportGenerator.new(report_type: "dpg_contacts_unlinked_from_gec").preview

    assert_equal 2, preview[:total_count]
    names = preview[:rows].map { |row| row[2] }
    assert_includes names, @unlinked_contact.first_name
    assert_includes names, @possible_match.first_name
  end

  test "GEC voters not in DPG report excludes linked voters" do
    preview = ReportGenerator.new(report_type: "gec_voters_not_in_dpg").preview

    assert_equal 1, preview[:total_count]
    assert_equal @unlinked_voter.voter_registration_number, preview[:rows].first[8]
  end

  test "possible GEC matches report exposes manual review notes" do
    preview = ReportGenerator.new(report_type: "possible_gec_matches").preview

    assert_equal 1, preview[:total_count]
    assert_equal @possible_match.first_name, preview[:rows].first[2]
    assert_match "Candidates: 2", preview[:rows].first.last
  end

  test "DPG GEC mismatch report shows linked contacts with conflicting DPG and official geography" do
    dpg_village = Village.find_or_create_by!(name: "Barrigada")
    dpg_precinct = Precinct.find_or_create_by!(village: dpg_village, number: "15C")
    @linked_contact.update!(street_address: "999 Different Address", village: dpg_village, precinct: dpg_precinct)

    preview = ReportGenerator.new(report_type: "dpg_gec_mismatches").preview

    assert_equal 1, preview[:total_count]
    row = preview[:rows].first
    assert_includes preview[:columns], "Mismatch Type"
    assert_equal @linked_contact.id, row[0]
    assert_equal @linked_voter.id, row[1]
    assert_includes row[13], "Village"
    assert_includes row[13], "Precinct"
    assert_includes row[13], "Address"
    assert_match "Review", row[14]
  end

  test "support list separates DPG assignment from linked GEC geography" do
    dpg_village = Village.find_or_create_by!(name: "Barrigada")
    dpg_precinct = Precinct.find_or_create_by!(village: dpg_village, number: "15C")
    @linked_contact.update!(village: dpg_village, precinct: dpg_precinct)

    preview = ReportGenerator.new(report_type: "support_list").preview
    row = preview[:rows].find { |values| values[0] == @linked_contact.last_name && values[1] == @linked_contact.first_name }

    assert_includes preview[:columns], "DPG Village"
    assert_includes preview[:columns], "GEC Village"
    assert_equal dpg_village.name, row[5]
    assert_equal dpg_precinct.number, row[6]
    assert_equal @linked_voter.voter_registration_number, row[7]
    assert_equal @village.name, row[8]
    assert_equal @precinct.number, row[9]
    assert_equal @linked_voter.address, row[10]
  end
end
