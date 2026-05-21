# frozen_string_literal: true

require "test_helper"

class Api::V1::QuotaPeriodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      clerk_id: "clerk-quota-admin-#{SecureRandom.hex(4)}",
      email: "quota-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Quota Admin",
      role: "campaign_admin"
    )
    @cycle = CampaignCycle.create!(
      name: "2026 DPG Organizing Cycle",
      cycle_type: "organizing",
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 12, 31),
      status: "active"
    )
  end

  test "admin can create and list quota periods" do
    assert_difference -> { QuotaPeriod.count }, 1 do
      post "/api/v1/quota_periods",
        params: {
          quota_period: {
            name: "Quota Period 1",
            start_date: "2026-05-01",
            end_date: "2026-05-31",
            due_date: "2026-06-03",
            quota_target: 250,
            status: "open"
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :created
    assert_equal "Quota Period 1", response.parsed_body.dig("quota_period", "name")
    assert_equal true, response.parsed_body.dig("quota_period", "active")

    get "/api/v1/quota_periods", headers: auth_headers(@admin)
    assert_response :success
    assert_equal 1, response.parsed_body["quota_periods"].length
    assert_equal "Quota Period 1", response.parsed_body.dig("active_quota_period", "name")
  end

  test "active quota period cannot be archived" do
    period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: "Active Period",
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      due_date: Date.new(2026, 6, 3),
      status: "open"
    )

    post "/api/v1/quota_periods/#{period.id}/archive", headers: auth_headers(@admin), as: :json

    assert_response :unprocessable_entity
    assert_equal "open", period.reload.status
    assert_equal "quota_period_archive_failed", response.parsed_body["code"]
  end

  test "closed quota period can be archived" do
    period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: "Closed Period",
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      due_date: Date.new(2026, 6, 3),
      status: "closed"
    )

    post "/api/v1/quota_periods/#{period.id}/archive", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal "archived", period.reload.status
  end

  test "only one period can be open at a time unless activated" do
    first = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: "Period 1",
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      due_date: Date.new(2026, 6, 3),
      status: "open"
    )
    second = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: "Period 2",
      start_date: Date.new(2026, 6, 1),
      end_date: Date.new(2026, 6, 30),
      due_date: Date.new(2026, 7, 3),
      status: "closed"
    )

    post "/api/v1/quota_periods/#{second.id}/activate", headers: auth_headers(@admin), as: :json

    assert_response :success
    assert_equal "closed", first.reload.status
    assert_equal "open", second.reload.status
  end
end
