# frozen_string_literal: true

require "test_helper"

class QuotaPeriodTest < ActiveSupport::TestCase
  setup do
    @campaign = Campaign.create!(
      name: "Quota Campaign",
      election_year: 2026,
      status: "active"
    )
    @cycle = CampaignCycle.create!(
      name: "2026 Primary", cycle_type: "primary",
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31)
    )
    @period = QuotaPeriod.create!(
      campaign_cycle: @cycle, name: "February 2026",
      start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28),
      due_date: Date.new(2026, 2, 23), quota_target: 6000
    )
    @village = Village.find_or_create_by!(name: "Barrigada")
  end

  test "eligible_count returns approved supporters in period regardless of gec match" do
    s = Supporter.create!(
      first_name: "Juan", last_name: "Cruz", village: @village,
      contact_number: "671-555-0001", source: "staff_entry",
      status: "active", quota_period: @period,
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "flagged"
    )

    assert_equal 1, @period.eligible_count
    assert_equal 0, @period.matched_count
  end

  test "eligible_count falls back to reviewed_at for legacy approved supporters without period assignment" do
    Supporter.create!(
      first_name: "Legacy", last_name: "Approved", village: @village,
      contact_number: "671-555-0002", source: "staff_entry",
      status: "active",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "verified",
      reviewed_at: Time.zone.parse("2026-02-10 12:00:00")
    )

    assert_equal 1, @period.eligible_count
    assert_equal 1, @period.matched_count
  end

  test "submit snapshots counts" do
    VillageQuota.create!(quota_period: @period, village: @village, target: 300)

    @period.submit!
    @period.reload

    assert_equal "submitted", @period.status
    assert @period.submission_summary["submitted_at"].present?
  end

  test "overdue and due_soon" do
    past_period = QuotaPeriod.create!(
      campaign_cycle: @cycle, name: "January 2026",
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 31),
      due_date: 1.week.ago.to_date, quota_target: 6000
    )

    assert past_period.overdue?

    future_period = QuotaPeriod.create!(
      campaign_cycle: @cycle, name: "December 2026",
      start_date: Date.new(2026, 12, 1), end_date: Date.new(2026, 12, 31),
      due_date: Date.new(2026, 12, 23), quota_target: 6000
    )
    refute future_period.overdue?
  end

  test "village_breakdown returns per-village data" do
    VillageQuota.create!(quota_period: @period, village: @village, target: 300)

    breakdown = @period.village_breakdown
    assert_equal 1, breakdown.size
    assert_equal "Barrigada", breakdown.first[:village_name]
    assert_equal 300, breakdown.first[:target]
    assert_equal 0, breakdown.first[:eligible]
  end

  test "effective_village_targets falls back to legacy quota rows for the current editable period when period rows are missing" do
    @period.update!(
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month
    )
    Quota.create!(
      campaign: @campaign,
      village: @village,
      target_count: 450,
      period: "monthly"
    )

    assert_equal({ @village.id => 450 }, @period.effective_village_targets(village_ids: [ @village.id ]))

    breakdown = @period.village_breakdown
    assert_equal 1, breakdown.size
    assert_equal 450, breakdown.first[:target]
  end

  test "past locked periods do not fall back to legacy quota rows" do
    Quota.create!(
      campaign: @campaign,
      village: @village,
      target_count: 450,
      period: "monthly"
    )

    assert_equal({}, @period.effective_village_targets(village_ids: [ @village.id ]))
    assert_equal [], @period.village_breakdown
    assert_equal true, @period.locked?
    assert_equal false, @period.editable?
  end

  test "editable and locked follow Guam local date boundaries" do
    march_period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: "March 2026",
      start_date: Date.new(2026, 3, 1),
      end_date: Date.new(2026, 3, 31),
      due_date: Date.new(2026, 3, 23),
      quota_target: 6000,
      status: "open"
    )

    assert_equal "Pacific/Guam", Time.zone.tzinfo.name

    travel_to Time.zone.local(2026, 3, 31, 23, 59, 0) do
      assert_equal Date.new(2026, 3, 31), Date.current
      assert_equal true, march_period.editable?
      assert_equal false, march_period.locked?
    end

    travel_to Time.zone.local(2026, 4, 1, 0, 1, 0) do
      assert_equal Date.new(2026, 4, 1), Date.current
      assert_equal false, march_period.editable?
      assert_equal true, march_period.locked?
    end
  end
end
