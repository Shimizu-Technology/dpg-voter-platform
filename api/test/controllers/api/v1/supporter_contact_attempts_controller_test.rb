require "test_helper"

class Api::V1::SupporterContactAttemptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @other_village = Village.find_or_create_by!(name: "Dededo")
    @admin = User.create!(
      clerk_id: "clerk-contact-admin-#{SecureRandom.hex(4)}",
      email: "contact-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Contact Admin",
      role: "campaign_admin"
    )
    @leader = User.create!(
      clerk_id: "clerk-contact-leader-#{SecureRandom.hex(4)}",
      email: "contact-leader-#{SecureRandom.hex(4)}@example.com",
      name: "Contact Leader",
      role: "block_leader",
      assigned_village_id: @village.id
    )
    @supporter = Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "671-555-1010",
      village: @village,
      street_address: "123 Chalan Santo Papa",
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )
  end

  test "staff can log and list contact attempts" do
    assert_difference -> { SupporterContactAttempt.count }, 1 do
      post "/api/v1/supporters/#{@supporter.id}/contact_attempts",
        params: {
          contact_attempt: {
            channel: "in_person",
            outcome: "reached",
            note: "Met at the front door.",
            recorded_at: "2026-05-12T09:30:00+10:00"
          }
        },
        headers: auth_headers(@leader),
        as: :json
    end

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "in_person", payload.dig("contact_attempt", "channel")
    assert_equal "reached", payload.dig("contact_attempt", "outcome")

    audit_log = AuditLog.where(auditable: @supporter, action: "contact_attempt_logged").last
    assert_equal "in_person", audit_log.changed_data["channel"]

    get "/api/v1/supporters/#{@supporter.id}/contact_attempts", headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["contact_attempts"].length
    assert_equal "Contact Leader", payload["contact_attempts"].first["recorded_by_name"]
  end

  test "contact attempts respect village scoping" do
    other_supporter = Supporter.create!(
      first_name: "Pedro",
      last_name: "Santos",
      village: @other_village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )

    post "/api/v1/supporters/#{other_supporter.id}/contact_attempts",
      params: { contact_attempt: { channel: "call", outcome: "attempted" } },
      headers: auth_headers(@leader),
      as: :json

    assert_response :not_found
  end

  test "invalid contact attempt returns structured error" do
    post "/api/v1/supporters/#{@supporter.id}/contact_attempts",
      params: { contact_attempt: { channel: "fax", outcome: "maybe" } },
      headers: auth_headers(@admin),
      as: :json

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "contact_attempt_create_failed", payload["code"]
  end
end
