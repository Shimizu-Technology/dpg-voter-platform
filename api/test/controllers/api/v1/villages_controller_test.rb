# frozen_string_literal: true

require "test_helper"

class Api::V1::VillagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @village = Village.create!(
      name: "Tamuning",
      region: "Central"
    )
    Precinct.create!(village: @village, number: "15A", alpha_range: "A-K", registered_voters: 600)
    Precinct.create!(village: @village, number: "15B", alpha_range: "L-Z", registered_voters: 500)
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator-village",
      email: "coordinator-village@example.com",
      name: "Coordinator",
      role: "district_coordinator"
    )
  end

  test "index returns villages with computed registered_voters from precincts" do
    get "/api/v1/villages"

    assert_response :success
    villages = JSON.parse(response.body)["villages"]
    tamuning = villages.find { |v| v["name"] == "Tamuning" }
    assert_not_nil tamuning
    assert_equal 1100, tamuning["registered_voters"]
  end

  test "show returns village with precinct breakdown" do
    get "/api/v1/villages/#{@village.id}",
      headers: auth_headers(@coordinator)

    assert_response :success
    village = JSON.parse(response.body)["village"]
    assert_equal 1100, village["registered_voters"]
    assert_equal 2, village["precincts"].size
  end

  test "show returns official supporters and current period progress" do
    Campaign.create!(
      name: "Village Test Campaign",
      election_year: 2026,
      status: "active"
    )
    cycle = CampaignCycle.create!(
      name: "Village Test Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    period = QuotaPeriod.create!(
      campaign_cycle: cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 25
    )
    VillageQuota.create!(quota_period: period, village: @village, target: 25)

    precinct_a = @village.precincts.order(:number).first
    precinct_b = @village.precincts.order(:number).last

    Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "6715551101",
      village: @village,
      precinct: precinct_a,
      source: "staff_entry",
      status: "active",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "verified",
      quota_period: period
    )
    Supporter.create!(
      first_name: "Jose",
      last_name: "Santos",
      contact_number: "6715551102",
      village: @village,
      precinct: precinct_b,
      source: "bulk_import",
      status: "active",
      review_status: "approved",
      public_review_status: "not_applicable",
      verification_status: "unverified",
      quota_period: period
    )
    Supporter.create!(
      first_name: "Pending",
      last_name: "Staff",
      contact_number: "6715551103",
      village: @village,
      source: "staff_entry",
      status: "active",
      review_status: "pending",
      public_review_status: "not_applicable",
      verification_status: "unverified"
    )
    Supporter.create!(
      first_name: "Pending",
      last_name: "Public",
      contact_number: "6715551104",
      village: @village,
      source: "public_signup",
      status: "active",
      intake_status: "pending_public_review",
      review_status: "pending",
      public_review_status: "pending",
      verification_status: "unverified"
    )

    get "/api/v1/villages/#{@village.id}",
      headers: auth_headers(@coordinator)

    assert_response :success
    village = JSON.parse(response.body)["village"]
    assert_equal 2, village["official_supporters_count"]
    assert_equal 1, village["matched_to_gec_count"]
    assert_equal 2, village["current_period_progress"]
    assert_equal 25, village["current_period_target"]
    assert_equal 1, village["team_pending_count"]
    assert_equal 1, village["public_pending_count"]
    assert_equal 2, village["supporter_count"]
    assert_equal 1, village["precincts"].find { |row| row["number"] == "15A" }["supporter_count"]
  end

  test "village update route does not exist" do
    patch "/api/v1/villages/#{@village.id}",
      params: { village: { name: "New Name" } },
      headers: auth_headers(@coordinator)

    assert_response :not_found
  end
end
