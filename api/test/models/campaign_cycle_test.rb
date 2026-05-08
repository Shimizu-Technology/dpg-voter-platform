# frozen_string_literal: true

require "test_helper"

class CampaignCycleTest < ActiveSupport::TestCase
  test "validates required fields" do
    cycle = CampaignCycle.new
    assert_not cycle.valid?
    assert_includes cycle.errors[:name], "can't be blank"
    assert_includes cycle.errors[:start_date], "can't be blank"
    assert_includes cycle.errors[:end_date], "can't be blank"
  end

  test "end_date must be after start_date" do
    cycle = CampaignCycle.new(
      name: "Test", cycle_type: "primary",
      start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 1, 1)
    )
    assert_not cycle.valid?
    assert_includes cycle.errors[:end_date], "must be after start date"
  end

  test "generates monthly periods" do
    cycle = CampaignCycle.create!(
      name: "2026 Primary", cycle_type: "primary",
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 6, 30),
      monthly_quota_target: 6000
    )

    cycle.generate_periods!

    assert_equal 6, cycle.quota_periods.count
    jan = cycle.quota_periods.find_by(name: "January 2026")
    assert_equal Date.new(2026, 1, 1), jan.start_date
    assert_equal Date.new(2026, 1, 31), jan.end_date
    assert_equal Date.new(2026, 1, 23), jan.due_date
    assert_equal 6000, jan.quota_target
    assert_equal "open", jan.status
  end

  test "generates periods with village targets" do
    village = Village.find_or_create_by!(name: "Barrigada")
    cycle = CampaignCycle.create!(
      name: "2026 Primary", cycle_type: "primary",
      start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 3, 31)
    )

    cycle.generate_periods!(village_targets: { village.id => 300 })

    assert_equal 2, cycle.quota_periods.count
    feb = cycle.quota_periods.find_by(name: "February 2026")
    assert_equal 1, feb.village_quotas.count
    assert_equal 300, feb.village_quotas.first.target
  end

  test "current scope finds active cycle" do
    CampaignCycle.create!(
      name: "2026 Primary", cycle_type: "primary",
      start_date: 1.month.ago.to_date, end_date: 6.months.from_now.to_date
    )

    assert_equal 1, CampaignCycle.current.count
  end

  test "due_day configurable via settings" do
    cycle = CampaignCycle.new(settings: { "due_day" => 15 })
    assert_equal 15, cycle.due_day

    default_cycle = CampaignCycle.new
    assert_equal 23, default_cycle.due_day
  end

  test "current_quota_period prefers the active current cycle over archived overlapping periods" do
    archived_cycle = CampaignCycle.create!(
      name: "Archived General",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "archived"
    )
    archived_period = QuotaPeriod.create!(
      campaign_cycle: archived_cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 6000
    )

    active_cycle = CampaignCycle.create!(
      name: "Active Primary",
      cycle_type: "primary",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    active_period = QuotaPeriod.create!(
      campaign_cycle: active_cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 6000
    )

    assert_equal active_period.id, CampaignCycle.current_quota_period.id
    assert_not_equal archived_period.id, CampaignCycle.current_quota_period.id
  end
end
