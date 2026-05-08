require "test_helper"

class GecVettingServiceTest < ActiveSupport::TestCase
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @other_village = Village.find_or_create_by!(name: "Dededo")
    @precinct = Precinct.find_or_create_by!(village: @village, number: "1")
    @alternate_precinct = Precinct.find_or_create_by!(village: @village, number: "2")

    # Create GEC voter records
    @gec_voter = GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      precinct: @precinct,
      precinct_number: @precinct.number,
      village_name: "Barrigada",
      voter_registration_number: "VR12345",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )

    GecVoter.create!(
      first_name: "Maria",
      last_name: "Santos",
      dob: Date.new(1990, 6, 20),
      village_name: "Dededo",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
  end

  test "auto-verifies exact match" do
    supporter = create_supporter(first_name: "Juan", last_name: "Cruz", dob: Date.new(1985, 3, 15), village: @village)

    result = GecVettingService.new(supporter).call

    assert_equal :auto_verified, result.status
    supporter.reload
    assert_equal "verified", supporter.verification_status
    assert supporter.registered_voter
    assert_equal "matched_current_gec", supporter.verification_reason
    assert_equal @precinct.id, supporter.precinct_id
  end

  test "auto-verification realigns supporter precinct to matched gec voter" do
    supporter = create_supporter(first_name: "Juan", last_name: "Cruz", dob: Date.new(1985, 3, 15), village: @village)
    supporter.update_columns(precinct_id: @alternate_precinct.id)

    result = GecVettingService.new(supporter).call

    assert_equal :auto_verified, result.status
    assert_equal @precinct.id, supporter.reload.precinct_id
  end

  test "flags different village as referral" do
    supporter = create_supporter(first_name: "Juan", last_name: "Cruz", dob: Date.new(1985, 3, 15), village: @other_village)

    result = GecVettingService.new(supporter).call

    assert_equal :referral, result.status
    supporter.reload
    assert_equal "flagged", supporter.verification_status
    assert supporter.registered_voter
    assert_equal @village.id, supporter.referred_from_village_id
    assert_equal "village_mismatch", supporter.verification_reason
  end

  test "marks unregistered when no match" do
    supporter = create_supporter(first_name: "Unknown", last_name: "Person", dob: Date.new(2000, 1, 1), village: @village)

    result = GecVettingService.new(supporter).call

    assert_equal :unregistered, result.status
    supporter.reload
    assert_not supporter.registered_voter
    assert_equal "no_gec_match", supporter.verification_reason
  end

  test "marks unregistered clears stale verified and referral state" do
    supporter = create_supporter(first_name: "Unknown", last_name: "Person", dob: Date.new(2000, 1, 1), village: @village)
    supporter.update_columns(
      verification_status: "verified",
      registered_voter: true,
      referred_from_village_id: @other_village.id,
      verified_at: 1.day.ago
    )

    result = GecVettingService.new(supporter).call

    assert_equal :unregistered, result.status
    supporter.reload
    assert_equal "unverified", supporter.verification_status
    assert_equal false, supporter.registered_voter
    assert_nil supporter.referred_from_village_id
    assert_nil supporter.verified_at
    assert_equal "no_gec_match", supporter.verification_reason
  end

  test "skips when no GEC data loaded" do
    GecVoter.delete_all

    supporter = create_supporter(first_name: "Juan", last_name: "Cruz", village: @village)

    result = GecVettingService.new(supporter).call

    assert_equal :skipped, result.status
  end

  test "auto-vets on supporter creation via callback" do
    supporter = Supporter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      contact_number: "671-555-0001",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown"
    )

    supporter.reload
    assert_equal "verified", supporter.verification_status
    assert supporter.registered_voter
  end

  test "case-insensitive matching" do
    supporter = create_supporter(first_name: "JUAN", last_name: "CRUZ", dob: Date.new(1985, 3, 15), village: @village)

    result = GecVettingService.new(supporter).call

    assert_equal :auto_verified, result.status
  end

  test "flags high-confidence multi-candidate birth-year matches for manual review" do
    GecVoter.delete_all

    2.times do |i|
      GecVoter.create!(
        first_name: "Juan",
        last_name: "Cruz",
        dob: Date.new(1985, 1, 1),
        birth_year: 1985,
        village_name: "Barrigada",
        voter_registration_number: "VRX#{i + 1}",
        gec_list_date: Date.new(2026, 2, 25),
        imported_at: Time.current,
        status: "active"
      )
    end

    supporter = create_supporter(first_name: "Juan", last_name: "Cruz", dob: Date.new(1985, 3, 15), village: @village)

    result = GecVettingService.new(supporter).call

    assert_equal :flagged, result.status
    assert_equal 2, result.match_count
    supporter.reload
    assert_equal "flagged", supporter.verification_status
    assert supporter.registered_voter
    assert_equal "multiple_matches", supporter.verification_reason
  end

  test "uses neutral needs review reason for unknown automated confidence" do
    supporter = create_supporter(first_name: "Mystery", last_name: "Match", dob: Date.new(1985, 3, 15), village: @village)

    original_find_matches = GecVoter.method(:find_matches)
    GecVoter.define_singleton_method(:find_matches) do |**|
      [ {
        gec_voter: @gec_voter,
        confidence: :unknown,
        match_type: :mystery,
        match_count: 1
      } ]
    end

    begin
      result = GecVettingService.new(supporter).call

      assert_equal :flagged, result.status
    ensure
      GecVoter.define_singleton_method(:find_matches, original_find_matches)
    end

    supporter.reload
    assert_equal "needs_manual_review", supporter.verification_reason
    assert_equal "unknown", supporter.verification_reason_metadata["confidence"]
    assert_equal "mystery", supporter.verification_reason_metadata["match_type"]
  end

  test "uses needs review reason for single name-year-only match" do
    supporter = create_supporter(first_name: "Jordan", last_name: "Onlyyear", dob: Date.new(1985, 3, 15), village: @village)

    original_find_matches = GecVoter.method(:find_matches)
    GecVoter.define_singleton_method(:find_matches) do |**|
      [ {
        gec_voter: @gec_voter,
        confidence: :medium,
        match_type: :name_year_only,
        match_count: 1
      } ]
    end

    begin
      result = GecVettingService.new(supporter).call

      assert_equal :flagged, result.status
      assert_equal "Possible GEC match with same birth year — needs manual review", result.details
    ensure
      GecVoter.define_singleton_method(:find_matches, original_find_matches)
    end

    supporter.reload
    assert_equal "needs_manual_review", supporter.verification_reason
    assert_equal "medium", supporter.verification_reason_metadata["confidence"]
    assert_equal "name_year_only", supporter.verification_reason_metadata["match_type"]
    assert_equal 1, supporter.verification_reason_metadata["match_count"]
  end

  private

  def create_supporter(first_name:, last_name:, village:, dob: nil)
    Supporter.new(
      first_name: first_name,
      last_name: last_name,
      dob: dob,
      contact_number: "671-555-#{rand(1000..9999)}",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      verification_status: "unverified"
    ).tap { |s| s.save!(validate: true) }
  end
end
