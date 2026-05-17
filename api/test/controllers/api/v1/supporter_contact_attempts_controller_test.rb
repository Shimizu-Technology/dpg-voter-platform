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
    @data_manager = User.create!(
      clerk_id: "clerk-contact-data-#{SecureRandom.hex(4)}",
      email: "contact-data-#{SecureRandom.hex(4)}@example.com",
      name: "Contact Data",
      role: "data_team"
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
      contact_classification: "active_contact",
      support_status: "supporter",
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

  test "logging a contact attempt starts open follow-up lanes" do
    @supporter.update!(
      registered_voter_status: "not_sure",
      registered_voter: false,
      volunteer_status: "interested",
      registration_outreach_status: nil,
      registration_outreach_date: nil,
      support_follow_up_status: nil,
      support_follow_up_date: nil
    )

    post "/api/v1/supporters/#{@supporter.id}/contact_attempts",
      params: {
        contact_attempt: {
          channel: "call",
          outcome: "reached",
          note: "Talked through registration and volunteer interest.",
          recorded_at: "2026-05-12T09:30:00+10:00"
        }
      },
      headers: auth_headers(@leader),
      as: :json

    assert_response :created
    @supporter.reload
    assert_equal "contacted", @supporter.registration_outreach_status
    assert_equal Time.zone.parse("2026-05-12T09:30:00+10:00").to_i, @supporter.registration_outreach_date.to_i
    assert_equal "in_progress", @supporter.support_follow_up_status
    assert_equal Time.zone.parse("2026-05-12T09:30:00+10:00").to_i, @supporter.support_follow_up_date.to_i

    audit_log = AuditLog.where(auditable: @supporter, action: "contact_attempt_logged").last
    follow_up_changes = audit_log.changed_data["follow_up_status"]
    assert_equal [ nil, "contacted" ], follow_up_changes["registration_outreach_status"]
    assert_equal [ nil, "in_progress" ], follow_up_changes["support_follow_up_status"]
  end

  test "logging a contact attempt preserves resolved follow-up lanes" do
    @supporter.update!(
      registered_voter_status: "no",
      registered_voter: false,
      volunteer_status: "interested",
      registration_outreach_status: "registered",
      registration_outreach_date: 2.days.ago,
      support_follow_up_status: "completed",
      support_follow_up_date: 1.day.ago
    )

    post "/api/v1/supporters/#{@supporter.id}/contact_attempts",
      params: {
        contact_attempt: {
          channel: "sms",
          outcome: "reached",
          note: "Confirmed no further help needed."
        }
      },
      headers: auth_headers(@leader),
      as: :json

    assert_response :created
    @supporter.reload
    assert_equal "registered", @supporter.registration_outreach_status
    assert_equal "completed", @supporter.support_follow_up_status

    audit_log = AuditLog.where(auditable: @supporter, action: "contact_attempt_logged").last
    assert_nil audit_log.changed_data["follow_up_status"]
  end

  test "contact attempts respect village scoping" do
    other_supporter = Supporter.create!(
      first_name: "Pedro",
      last_name: "Santos",
      village: @other_village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
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

  test "admin can edit contact attempts and audit before after values" do
    attempt = @supporter.supporter_contact_attempts.create!(
      recorded_by_user: @leader,
      channel: "call",
      outcome: "attempted",
      note: "Left voicemail.",
      recorded_at: Time.zone.parse("2026-05-12T09:30:00+10:00")
    )

    patch "/api/v1/supporters/#{@supporter.id}/contact_attempts/#{attempt.id}",
      params: {
        contact_attempt: {
          channel: "in_person",
          outcome: "reached",
          note: "Corrected after reviewing notes.",
          recorded_at: "2026-05-12T10:45:00+10:00"
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "in_person", payload.dig("contact_attempt", "channel")
    assert_equal "reached", payload.dig("contact_attempt", "outcome")
    assert_equal "Contact Leader", payload.dig("contact_attempt", "recorded_by_name")

    audit_log = AuditLog.where(auditable: @supporter, action: "contact_attempt_updated").last
    assert_equal [ "call", "in_person" ], audit_log.changed_data["channel"]
    assert_equal [ "attempted", "reached" ], audit_log.changed_data["outcome"]
    assert_equal [ "Left voicemail.", "Corrected after reviewing notes." ], audit_log.changed_data["note"]
    assert_equal @admin.id, audit_log.actor_user_id
  end

  test "data manager can edit contact attempts" do
    attempt = @supporter.supporter_contact_attempts.create!(
      recorded_by_user: @leader,
      channel: "sms",
      outcome: "attempted",
      recorded_at: Time.current
    )

    patch "/api/v1/supporters/#{@supporter.id}/contact_attempts/#{attempt.id}",
      params: { contact_attempt: { channel: "sms", outcome: "reached", note: "They replied yes.", recorded_at: Time.current.iso8601 } },
      headers: auth_headers(@data_manager),
      as: :json

    assert_response :success
    assert_equal "reached", attempt.reload.outcome
  end

  test "field users cannot edit contact attempts" do
    attempt = @supporter.supporter_contact_attempts.create!(
      recorded_by_user: @leader,
      channel: "call",
      outcome: "attempted",
      recorded_at: Time.current
    )

    patch "/api/v1/supporters/#{@supporter.id}/contact_attempts/#{attempt.id}",
      params: { contact_attempt: { channel: "call", outcome: "reached", recorded_at: Time.current.iso8601 } },
      headers: auth_headers(@leader),
      as: :json

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "contact_attempt_edit_access_required", payload["code"]
    assert_equal "attempted", attempt.reload.outcome
  end
end
