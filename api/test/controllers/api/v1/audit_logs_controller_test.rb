require "test_helper"

class Api::V1::AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      clerk_id: "clerk-audit-admin",
      email: "audit-admin@example.com",
      name: "Audit Admin",
      role: "campaign_admin"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-audit-coordinator",
      email: "audit-coord@example.com",
      name: "Audit Coordinator",
      role: "district_coordinator"
    )
    @chief = User.create!(
      clerk_id: "clerk-audit-chief",
      email: "audit-chief@example.com",
      name: "Audit Chief",
      role: "village_chief"
    )
    @village = Village.create!(name: "Audit Village")
    @supporter = Supporter.create!(
      first_name: "Ana",
      last_name: "Cruz",
      contact_number: "671-555-1212",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      status: "active",
      turnout_status: "unknown",
      verification_status: "unverified"
    )

    AuditLog.create!(
      auditable: @supporter,
      actor_user: @admin,
      action: "created",
      changed_data: { "first_name" => { "from" => nil, "to" => "Ana" } }
    )
  end

  test "admin can list audit logs" do
    get "/api/v1/audit_logs", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["audit_logs"].any?
    assert_equal "Supporter", payload.dig("audit_logs", 0, "auditable_type")
  end

  test "coordinator cannot list audit logs" do
    get "/api/v1/audit_logs", headers: auth_headers(@coordinator)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "audit_logs_access_required", payload["code"]
  end

  test "village chief cannot list audit logs" do
    get "/api/v1/audit_logs", headers: auth_headers(@chief)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "audit_logs_access_required", payload["code"]
  end
end
