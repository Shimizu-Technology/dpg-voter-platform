require "test_helper"

class Api::V1::QuotasControllerTest < ActionDispatch::IntegrationTest
  def setup
    @campaign = Campaign.create!(
      name: "Test Campaign",
      election_year: 2026,
      status: "active"
    )
    @village = Village.create!(
      name: "Tamuning",
      region: "Central"
    )
    Precinct.create!(village: @village, number: "Q1", alpha_range: "A-Z", registered_voters: 1234)
    @second_village = Village.create!(
      name: "Barrigada",
      region: "Central"
    )
    Precinct.create!(village: @second_village, number: "Q2", alpha_range: "A-Z", registered_voters: 2345)
    @quota = Quota.create!(
      campaign: @campaign,
      village: @village,
      period: "quarterly",
      target_count: 250
    )
    @second_quota = Quota.create!(
      campaign: @campaign,
      village: @second_village,
      period: "quarterly",
      target_count: 175
    )
    @admin = User.create!(
      clerk_id: "clerk-admin-quota",
      email: "quota-admin@example.com",
      name: "Quota Admin",
      role: "campaign_admin"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-coordinator-quota",
      email: "quota-coordinator@example.com",
      name: "Quota Coordinator",
      role: "district_coordinator"
    )
    @leader = User.create!(
      clerk_id: "clerk-leader-quota",
      email: "quota-leader@example.com",
      name: "Quota Leader",
      role: "block_leader"
    )
    @cycle = CampaignCycle.create!(
      name: "Quota Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    @period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 6000
    )
    GecVoter.create!(
      first_name: "Latest",
      last_name: "Voter",
      village_name: @village.name,
      village: @village,
      voter_registration_number: "VRN-1001",
      status: "active",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
  end

  test "non coordinator cannot access quotas index" do
    get "/api/v1/quotas", headers: auth_headers(@leader)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "coordinator_access_required", payload["code"]
  end

  test "coordinator can list quotas" do
    get "/api/v1/quotas", headers: auth_headers(@coordinator)

    assert_response :success
    payload = JSON.parse(response.body)
    row = payload["quotas"].find { |q| q["village_id"] == @village.id }
    assert_not_nil row
    assert_equal 250, row["target_count"]
    assert_equal @period.name, payload.dig("current_period", "name")
    assert_equal 425, payload.dig("current_period", "quota_target")
    assert_equal "2026-02-25", payload["latest_gec_list_date"]
  end

  test "admin can update existing quota and audit is written" do
    patch "/api/v1/quotas/#{@village.id}",
      params: { quota: { target_count: 375, change_note: "Adjusted weekly goal" } },
      headers: auth_headers(@admin)

    assert_response :success
    assert_equal 375, @quota.reload.target_count
    audit = AuditLog.where(auditable: @quota).order(created_at: :desc).first
    assert_not_nil audit
    assert_equal "updated", audit.action
    assert_equal 250, audit.changed_data.dig("target_count", "from")
    assert_equal 375, audit.changed_data.dig("target_count", "to")
    assert_equal @admin.id, audit.actor_user_id
    assert_equal "Adjusted weekly goal", audit.metadata["change_note"]
    assert_equal 375, @period.village_quotas.find_by!(village: @village).target
  end

  test "updating current month locks a full past period target snapshot before changing current period" do
    past_period = QuotaPeriod.create!(
      campaign_cycle: @cycle,
      name: (Date.current - 1.month).strftime("%B %Y"),
      start_date: (Date.current - 1.month).beginning_of_month,
      end_date: (Date.current - 1.month).end_of_month,
      due_date: (Date.current - 1.month).end_of_month,
      quota_target: 6000,
      status: "open"
    )

    patch "/api/v1/quotas/#{@village.id}",
      params: { quota: { target_count: 375 } },
      headers: auth_headers(@admin)

    assert_response :success
    assert_equal 250, past_period.village_quotas.find_by!(village: @village).target
    assert_equal 175, past_period.village_quotas.find_by!(village: @second_village).target
    assert_equal 375, @period.village_quotas.find_by!(village: @village).target
  end

  test "admin can create village quota when missing" do
    village = Village.create!(
      name: "Dededo",
      region: "North"
    )
    Precinct.create!(village: village, number: "Q2", alpha_range: "A-Z", registered_voters: 2222)

    assert_difference -> { Quota.count }, +1 do
      patch "/api/v1/quotas/#{village.id}",
        params: { quota: { target_count: 420 } },
        headers: auth_headers(@admin)
    end

    assert_response :success
    quota = Quota.find_by!(campaign: @campaign, village: village)
    assert_equal 420, quota.target_count
    assert_equal "quarterly", quota.period
  end

  test "invalid target_count is rejected" do
    patch "/api/v1/quotas/#{@village.id}",
      params: { quota: { target_count: 0 } },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "invalid_quota_target", payload["code"]
  end
end
