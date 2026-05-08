require "test_helper"

class ReportGeneratorTest < ActiveSupport::TestCase
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @village2 = Village.find_or_create_by!(name: "Dededo")

    @campaign = Campaign.find_or_create_by!(
      name: "Test Campaign",
      status: "active",
      election_year: 2026
    )

    Quota.find_or_create_by!(campaign: @campaign, village: @village) do |q|
      q.target_count = 100
      q.target_date = Date.new(2026, 8, 1)
      q.period = "monthly"
    end

    # Create verified team-input supporter
    @supporter = Supporter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      contact_number: "671-555-0001",
      dob: Date.new(1985, 3, 15),
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      verification_status: "verified",
      verified_at: Time.current,
      registered_voter: true,
      registered_voter_status: "yes",
      needs_voter_registration_help: true,
      registration_outreach_status: "registered",
      support_follow_up_status: "completed",
      referred_by_name: "Maria Cruz"
    )

    # Create a referral supporter (wrong village)
    @referral = Supporter.create!(
      first_name: "Ana",
      last_name: "Santos",
      contact_number: "671-555-0002",
      village: @village2,
      submitted_village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      verification_status: "flagged",
      registered_voter: true,
      registered_voter_status: "no",
      needs_absentee_ballot_help: true,
      registration_outreach_status: "contacted",
      support_follow_up_status: "in_progress"
    )

    # GEC voter data
    GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      village_name: "Barrigada",
      voter_registration_number: "VR12345",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
    @transferred_voter = GecVoter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      dob: Date.new(1980, 1, 1),
      village_name: "Barrigada",
      previous_village_name: "Dededo",
      voter_registration_number: "VR54321",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
    @mapping_issue_voter = GecVoter.create!(
      first_name: "Jose",
      last_name: "Santos",
      dob: Date.new(1979, 2, 2),
      village_name: GecImportService::UNASSIGNED_VILLAGE_NAME,
      previous_village_name: "Yigo",
      voter_registration_number: "VR99999",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
  end

  test "generates support list" do
    result = ReportGenerator.new(report_type: "support_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/support-list/, result[:filename])
  end

  test "generates support list filtered by village" do
    result = ReportGenerator.new(report_type: "support_list", village_id: @village.id).generate
    assert result[:package].is_a?(Axlsx::Package)
  end

  test "support list preview applies Becky filters and exposes Becky columns" do
    result = ReportGenerator.new(
      report_type: "support_list",
      registered_voter_status: "yes",
      support_need: "registration",
      registration_outreach_status: "registered",
      support_follow_up_status: "completed"
    ).preview

    assert_equal 1, result[:total_count]
    assert_equal "Juan", result[:rows].first[1]
    assert_includes result[:columns], "Self-Reported Voter Status"
    assert_includes result[:columns], "Campaign Requests"
    assert_includes result[:columns], "Registration Follow-Up Result"
    assert_includes result[:columns], "Support Follow-Up Result"
    assert_includes result[:rows].first, "Registered via follow-up"
    assert_includes result[:rows].first, "Completed"
  end

  test "generates purge list" do
    GecVoter.create!(
      first_name: "Removed",
      last_name: "Voter",
      village_name: "Barrigada",
      status: "removed",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )

    result = ReportGenerator.new(report_type: "purge_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/purge-list/, result[:filename])
  end

  test "generates transfer list" do
    result = ReportGenerator.new(report_type: "transfer_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/transfer-list/, result[:filename])
  end

  test "transfer preview uses GEC transfer rows instead of supporter referrals" do
    result = ReportGenerator.new(report_type: "transfer_list").preview
    assert_equal 1, result[:total_count]
    assert_equal "Maria", result[:rows].first[1]
    assert_equal "Dededo", result[:rows].first[4]
    assert_equal "Barrigada", result[:rows].first[5]
  end

  test "generates referral list" do
    result = ReportGenerator.new(report_type: "referral_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/referral-list/, result[:filename])
  end

  test "referral preview uses supporter village mismatch rows" do
    result = ReportGenerator.new(report_type: "referral_list").preview
    assert_equal 1, result[:total_count]
    assert_equal "Ana", result[:rows].first[1]
    assert_equal "Barrigada", result[:rows].first[4]
    assert_equal "Dededo", result[:rows].first[5]
  end

  test "referral preview applies Becky filters" do
    result = ReportGenerator.new(
      report_type: "referral_list",
      registered_voter_status: "no",
      support_need: "absentee",
      registration_outreach_status: "contacted",
      support_follow_up_status: "in_progress"
    ).preview

    assert_equal 1, result[:total_count]
    assert_equal "Ana", result[:rows].first[1]
    assert_includes result[:rows].first, "Absentee"
    assert_includes result[:rows].first, "In progress"
  end

  test "generates mapping issues list" do
    result = ReportGenerator.new(report_type: "mapping_issues_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/village-mapping-issues/, result[:filename])
  end

  test "mapping issues preview isolates unassigned transfer rows" do
    result = ReportGenerator.new(report_type: "mapping_issues_list").preview
    assert_equal 1, result[:total_count]
    assert_equal "Jose", result[:rows].first[1]
    assert_equal "Yigo", result[:rows].first[4]
    assert_equal GecImportService::UNASSIGNED_VILLAGE_NAME, result[:rows].first[5]
  end

  test "generates quota summary" do
    result = ReportGenerator.new(report_type: "quota_summary").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/quota-summary/, result[:filename])
  end

  test "quota summary ignores stale campaign id when current period exists" do
    cycle = CampaignCycle.create!(
      name: "Quota Summary Test Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    QuotaPeriod.create!(
      campaign_cycle: cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 100
    )

    result = ReportGenerator.new(report_type: "quota_summary", campaign_id: -1).generate
    assert result[:package].is_a?(Axlsx::Package)

    preview = ReportGenerator.new(report_type: "quota_summary", campaign_id: -1).preview
    assert preview[:rows].is_a?(Array)
  end

  test "raises on unknown report type" do
    assert_raises(ArgumentError) do
      ReportGenerator.new(report_type: "nonexistent").generate
    end
  end

  test "purge list handles no GEC data" do
    GecVoter.delete_all
    result = ReportGenerator.new(report_type: "purge_list").generate
    assert result[:package].is_a?(Axlsx::Package)
    assert_match(/purge-list/, result[:filename])
  end
end
