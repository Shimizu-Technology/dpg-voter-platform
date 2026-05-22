# frozen_string_literal: true

require "test_helper"

class CampaignCycleTest < ActiveSupport::TestCase
  test "current_or_create_default reactivates an archived default cycle" do
    archived_cycle = CampaignCycle.create!(
      name: CampaignCycle.default_cycle_name,
      cycle_type: "organizing",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "archived"
    )

    assert_no_difference -> { CampaignCycle.count } do
      cycle = CampaignCycle.current_or_create_default!

      assert_equal archived_cycle.id, cycle.id
      assert_equal "active", cycle.status
    end
  end
end
