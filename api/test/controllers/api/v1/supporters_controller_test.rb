require "test_helper"

class Api::V1::SupportersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      clerk_id: "clerk-supporters-admin-#{SecureRandom.hex(4)}",
      email: "supporters-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Supporters Admin",
      role: "campaign_admin"
    )
  end

  test "export is limited to data managers and admins" do
    village = Village.find_or_create_by!(name: "Yona")
    field_user = User.create!(
      clerk_id: "clerk-field-export-#{SecureRandom.hex(4)}",
      email: "field-export-#{SecureRandom.hex(4)}@example.com",
      name: "Field Export",
      role: "block_leader",
      assigned_village_id: village.id
    )
    data_manager = User.create!(
      clerk_id: "clerk-data-export-#{SecureRandom.hex(4)}",
      email: "data-export-#{SecureRandom.hex(4)}@example.com",
      name: "Data Export",
      role: "data_team"
    )

    get "/api/v1/supporters/export", headers: auth_headers(field_user), as: :json
    assert_response :forbidden
    assert_equal "supporter_export_access_required", response.parsed_body["code"]

    get "/api/v1/supporters/export", headers: auth_headers(data_manager)
    assert_response :success
  end

  test "manual GEC verification links official voter geography while preserving submitted contact details" do
    submitted_village = Village.find_or_create_by!(name: "Barrigada")
    gec_village = Village.find_or_create_by!(name: "Hagåtña")
    gec_precinct = Precinct.find_or_create_by!(village: gec_village, number: "1") do |precinct|
      precinct.alpha_range = "A-Z"
    end
    gec_voter = GecVoter.create!(
      first_name: "Leon",
      middle_name: "A.",
      last_name: "Shimizu",
      dob: Date.new(1999, 7, 20),
      birth_year: 1999,
      address: "PO BOX 761",
      village: gec_village,
      village_name: gec_village.name,
      precinct: gec_precinct,
      precinct_number: gec_precinct.number,
      voter_registration_number: "78246",
      gec_list_date: Date.new(2026, 5, 13),
      imported_at: Time.current
    )
    supporter = Supporter.create!(
      first_name: "Leon",
      last_name: "Shimizu",
      contact_number: "+16714830219",
      dob: Date.new(1999, 7, 20),
      street_address: "221 Lirio Ave",
      village: submitted_village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    assert_equal "flagged", supporter.reload.verification_status
    assert_equal submitted_village.id, supporter.village_id
    assert_equal submitted_village.id, supporter.submitted_village_id

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@admin), as: :json

    assert_response :success
    candidate = response.parsed_body.dig("supporter", "gec_match_candidates").first
    assert_equal gec_voter.id, candidate["id"]
    assert_equal "Leon A. Shimizu", candidate["name"]
    assert_equal gec_village.name, candidate["village_name"]
    assert_equal gec_precinct.number, candidate["precinct_number"]

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "verified", gec_voter_id: gec_voter.id },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    supporter.reload
    assert_equal gec_voter.id, supporter.gec_voter_id
    assert_equal submitted_village.id, supporter.village_id
    assert_equal submitted_village.id, supporter.submitted_village_id
    assert_nil supporter.precinct_id
    assert_equal true, supporter.registered_voter
    assert_equal "yes", supporter.registered_voter_status
    assert_equal "manual_staff_verified", supporter.verification_reason
    assert_equal gec_voter.id, supporter.verification_reason_metadata["gec_voter_id"]
    assert_equal "Leon", supporter.first_name
    assert_nil supporter.middle_name
    assert_equal "Shimizu", supporter.last_name
    assert_equal "221 Lirio Ave", supporter.street_address
  end

  test "manual GEC verification can link an explicitly selected match candidate" do
    submitted_village = Village.find_or_create_by!(name: "Barrigada")
    first_gec_village = Village.find_or_create_by!(name: "Tamuning")
    second_gec_village = Village.find_or_create_by!(name: "Hagåtña")
    first_gec_voter = GecVoter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      birth_year: 1988,
      address: "100 Marine Dr",
      village: first_gec_village,
      village_name: first_gec_village.name,
      precinct_number: "17A",
      voter_registration_number: "100001",
      gec_list_date: Date.new(2026, 5, 13),
      imported_at: Time.current
    )
    selected_gec_voter = GecVoter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      birth_year: 1988,
      address: "PO BOX 500",
      village: second_gec_village,
      village_name: second_gec_village.name,
      precinct_number: "1",
      voter_registration_number: "100002",
      gec_list_date: Date.new(2026, 5, 13),
      imported_at: Time.current
    )
    supporter = Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "6715550101",
      dob: Date.new(1988, 1, 1),
      street_address: "123 Contact St",
      village: submitted_village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "verified", gec_voter_id: selected_gec_voter.id },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    supporter.reload
    assert_equal selected_gec_voter.id, supporter.gec_voter_id
    refute_equal first_gec_voter.id, supporter.gec_voter_id
    assert_equal submitted_village.id, supporter.village_id
    assert_equal "123 Contact St", supporter.street_address
    assert_equal selected_gec_voter.id, supporter.verification_reason_metadata["gec_voter_id"]
    assert_equal second_gec_village.name, supporter.verification_reason_metadata["gec_village_name"]
  end

  test "manual GEC verification rejects a selected voter outside the current candidate set" do
    submitted_village = Village.find_or_create_by!(name: "Barrigada")
    candidate_village = Village.find_or_create_by!(name: "Tamuning")
    wrong_village = Village.find_or_create_by!(name: "Dededo")
    GecVoter.create!(
      first_name: "Tasi",
      last_name: "Santos",
      birth_year: 1975,
      address: "100 Marine Dr",
      village: candidate_village,
      village_name: candidate_village.name,
      precinct_number: "17A",
      voter_registration_number: "200001",
      gec_list_date: Date.new(2026, 5, 13),
      imported_at: Time.current
    )
    wrong_voter = GecVoter.create!(
      first_name: "Different",
      last_name: "Person",
      birth_year: 1975,
      address: "999 Other Rd",
      village: wrong_village,
      village_name: wrong_village.name,
      precinct_number: "18A",
      voter_registration_number: "200002",
      gec_list_date: Date.new(2026, 5, 13),
      imported_at: Time.current
    )
    supporter = Supporter.create!(
      first_name: "Tasi",
      last_name: "Santos",
      contact_number: "6715550102",
      dob: Date.new(1975, 4, 2),
      village: submitted_village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "verified", gec_voter_id: wrong_voter.id },
      headers: auth_headers(@admin),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "gec_match_candidate_not_found", response.parsed_body["code"]
    assert_nil supporter.reload.gec_voter_id
  end

  test "review intake classifies contact and logs initial outreach" do
    village = Village.find_or_create_by!(name: "Dededo")
    supporter = Supporter.create!(
      first_name: "Malia",
      last_name: "Cruz",
      contact_number: "+16715551212",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      public_review_status: "pending",
      status: "active"
    )

    assert_difference -> { SupporterContactAttempt.count }, 1 do
      patch "/api/v1/supporters/#{supporter.id}/review_intake",
        params: {
          intake_review: {
            decision: "approve",
            contact_classification: "active_contact",
            support_status: "supporter",
            note: "Confirmed at event table.",
            contact_attempt: {
              channel: "in_person",
              outcome: "reached",
              note: "Talked through registration status."
            }
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :success
    supporter.reload
    assert_equal "active_contact", supporter.contact_classification
    assert_equal "supporter", supporter.support_status
    assert_equal "approved", supporter.review_status
    assert_equal "not_applicable", supporter.public_review_status
    assert_equal @admin.id, supporter.reviewed_by_user_id
    assert_equal @admin.id, supporter.classified_by_user_id
    assert_equal "in_person", supporter.supporter_contact_attempts.last.channel
    assert_equal "reached", supporter.supporter_contact_attempts.last.outcome
    assert_equal "intake_reviewed", AuditLog.where(auditable: supporter).last.action
  end

  test "review intake can reject invalid records" do
    village = Village.find_or_create_by!(name: "Yigo")
    supporter = Supporter.create!(
      first_name: "Bad",
      last_name: "Entry",
      contact_number: "+16715550000",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      public_review_status: "pending",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/review_intake",
      params: {
        intake_review: {
          decision: "reject",
          contact_classification: "invalid",
          support_status: "supporter",
          membership_status: "member",
          volunteer_status: "active",
          note: "Test submission."
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    supporter.reload
    assert_equal "invalid", supporter.contact_classification
    assert_equal "unknown", supporter.support_status
    assert_equal "not_member", supporter.membership_status
    assert_equal "unknown", supporter.volunteer_status
    assert_equal "rejected", supporter.review_status
    assert_equal "rejected", supporter.public_review_status
    refute_includes Supporter.contacts.pluck(:id), supporter.id
  end

  test "review intake rejects active contact classification for reject decision" do
    village = Village.find_or_create_by!(name: "Sinajana")
    supporter = Supporter.create!(
      first_name: "Reject",
      last_name: "Mismatch",
      contact_number: "+16715552222",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      public_review_status: "pending",
      status: "active"
    )

    assert_no_difference -> { AuditLog.count } do
      patch "/api/v1/supporters/#{supporter.id}/review_intake",
        params: {
          intake_review: {
            decision: "reject",
            contact_classification: "active_contact"
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :unprocessable_entity
    supporter.reload
    assert_equal "new_intake", supporter.contact_classification
    assert_equal "pending", supporter.review_status
    assert_equal "unknown", supporter.support_status
    assert_equal "invalid_intake_review_decision_classification", response.parsed_body["code"]
  end

  test "review intake rejects rejection classification for approve decision" do
    village = Village.find_or_create_by!(name: "Mangilao")
    supporter = Supporter.create!(
      first_name: "Approve",
      last_name: "Mismatch",
      contact_number: "+16715552333",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      public_review_status: "pending",
      status: "active"
    )

    assert_no_difference -> { AuditLog.count } do
      patch "/api/v1/supporters/#{supporter.id}/review_intake",
        params: {
          intake_review: {
            decision: "approve",
            contact_classification: "duplicate"
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :unprocessable_entity
    supporter.reload
    assert_equal "new_intake", supporter.contact_classification
    assert_equal "pending", supporter.review_status
    assert_equal "active", supporter.status
    assert_equal "invalid_intake_review_decision_classification", response.parsed_body["code"]
  end

  test "review intake requires complete initial outreach details when any outreach is provided" do
    village = Village.find_or_create_by!(name: "Piti")
    supporter = Supporter.create!(
      first_name: "Partial",
      last_name: "Outreach",
      contact_number: "+16715552323",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    assert_no_difference -> { SupporterContactAttempt.count } do
      assert_no_difference -> { AuditLog.count } do
        patch "/api/v1/supporters/#{supporter.id}/review_intake",
          params: {
            intake_review: {
              decision: "approve",
              contact_classification: "active_contact",
              contact_attempt: {
                note: "Reached at the village table."
              }
            }
          },
          headers: auth_headers(@admin),
          as: :json
      end
    end

    assert_response :unprocessable_entity
    supporter.reload
    assert_equal "new_intake", supporter.contact_classification
    assert_equal "pending", supporter.review_status
    assert_equal "contact_attempt_required", response.parsed_body["code"]
  end

  test "review intake rejects invalid classification" do
    village = Village.find_or_create_by!(name: "Mangilao")
    supporter = Supporter.create!(
      first_name: "Ari",
      last_name: "Test",
      contact_number: "+16715553333",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/review_intake",
      params: {
        intake_review: {
          decision: "approve",
          contact_classification: "maybe"
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :unprocessable_entity
    assert_equal "new_intake", supporter.reload.contact_classification
  end

  test "review intake rejects new intake as submitted review classification" do
    village = Village.find_or_create_by!(name: "Agat")
    supporter = Supporter.create!(
      first_name: "Still",
      last_name: "Pending",
      contact_number: "+16715553444",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/review_intake",
      params: {
        intake_review: {
          decision: "approve",
          contact_classification: "new_intake"
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :unprocessable_entity
    supporter.reload
    assert_equal "new_intake", supporter.contact_classification
    assert_equal "pending", supporter.review_status
  end

  test "review intake only accepts pending new intake records" do
    village = Village.find_or_create_by!(name: "Tamuning")
    supporter = Supporter.create!(
      first_name: "Reviewed",
      last_name: "Contact",
      contact_number: "+16715554444",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      support_status: "supporter",
      review_status: "approved",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}/review_intake",
      params: {
        intake_review: {
          decision: "reject",
          contact_classification: "archived"
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :conflict
    supporter.reload
    assert_equal "active_contact", supporter.contact_classification
    assert_equal "supporter", supporter.support_status
    assert_equal "active", supporter.status
  end

  test "canvass update atomically classifies contact and logs attempt" do
    village = Village.find_or_create_by!(name: "Inalåhan")
    supporter = Supporter.create!(
      first_name: "Door",
      last_name: "Knock",
      contact_number: "+16715556666",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      classified_at: 2.days.ago,
      classified_by_user: @admin,
      review_status: "approved",
      status: "active"
    )
    original_classified_at = supporter.classified_at

    assert_difference -> { SupporterContactAttempt.count }, 1 do
      patch "/api/v1/supporters/#{supporter.id}/canvass_update",
        params: {
          canvass_update: {
            contact_classification: "active_contact",
            support_status: "supporter",
            volunteer_status: "interested",
            contact_attempt: {
              channel: "in_person",
              outcome: "reached",
              note: "Wants to help next weekend."
            }
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :success
    supporter.reload
    assert_equal "active_contact", supporter.contact_classification
    assert_equal "supporter", supporter.support_status
    assert_equal "interested", supporter.volunteer_status
    assert_equal "in_progress", supporter.support_follow_up_status
    assert supporter.support_follow_up_date.present?
    assert_equal original_classified_at.to_i, supporter.classified_at.to_i
    assert_equal @admin.id, supporter.classified_by_user_id
    assert_equal "in_person", supporter.supporter_contact_attempts.last.channel
    audit_log = AuditLog.where(auditable: supporter).last
    assert_equal "household_canvass_logged", audit_log.action
    assert_equal [ nil, "in_progress" ], audit_log.changed_data.dig("follow_up", "support_follow_up_status")
  end

  test "village-scoped canvasser can log household canvass but cannot export contacts" do
    village = Village.find_or_create_by!(name: "Piti")
    supporter = Supporter.create!(
      first_name: "Village",
      last_name: "Canvass",
      contact_number: "+16715559990",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      classified_at: 1.day.ago,
      classified_by_user: @admin,
      review_status: "approved",
      status: "active"
    )
    canvasser = User.create!(
      clerk_id: "clerk-canvasser-log-#{SecureRandom.hex(4)}",
      email: "canvasser-log-#{SecureRandom.hex(4)}@example.com",
      name: "Village Canvasser",
      role: "block_leader",
      assigned_village_id: village.id
    )

    assert_difference -> { SupporterContactAttempt.count }, 1 do
      patch "/api/v1/supporters/#{supporter.id}/canvass_update",
        params: {
          canvass_update: {
            contact_classification: "active_contact",
            support_status: "supporter",
            volunteer_status: "not_interested",
            contact_attempt: {
              channel: "in_person",
              outcome: "reached"
            }
          }
        },
        headers: auth_headers(canvasser),
        as: :json
    end

    assert_response :success
    supporter.reload
    assert_equal "supporter", supporter.support_status
    assert_equal "not_interested", supporter.volunteer_status

    get "/api/v1/supporters/export", headers: auth_headers(canvasser), as: :json
    assert_response :forbidden
  end

  test "supporters index includes latest contact attempt summary" do
    village = Village.find_or_create_by!(name: "Sånta Rita-Sumai")
    supporter = Supporter.create!(
      first_name: "Latest",
      last_name: "Attempt",
      contact_number: "+16715559991",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      review_status: "approved",
      status: "active"
    )
    supporter.supporter_contact_attempts.create!(
      channel: "call",
      outcome: "attempted",
      recorded_at: 2.days.ago,
      recorded_by_user: @admin
    )
    latest = supporter.supporter_contact_attempts.create!(
      channel: "sms",
      outcome: "reached",
      note: "Confirmed support.",
      recorded_at: 1.hour.ago,
      recorded_by_user: @admin
    )

    get "/api/v1/supporters?search=Latest",
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    row = response.parsed_body["supporters"].find { |supporter_row| supporter_row["id"] == supporter.id }
    assert_not_nil row
    assert_equal supporter.id, row["id"]
    assert_equal latest.id, row.dig("latest_contact_attempt", "id")
    assert_equal "sms", row.dig("latest_contact_attempt", "channel")
    assert_equal @admin.name, row.dig("latest_contact_attempt", "recorded_by_name")
  end

  test "supporters index search matches first last and last first contact names" do
    village = Village.find_or_create_by!(name: "Barrigada")
    supporter = Supporter.create!(
      first_name: "Kameren",
      last_name: "Cruz",
      contact_number: "+16715550001",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      review_status: "approved",
      status: "active"
    )

    get "/api/v1/supporters?search=Kameren%20Cruz",
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    assert_includes response.parsed_body["supporters"].map { |row| row["id"] }, supporter.id

    get "/api/v1/supporters?search=Cruz,%20Kameren",
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    assert_includes response.parsed_body["supporters"].map { |row| row["id"] }, supporter.id
  end

  test "canvass update cannot bypass intake review" do
    village = Village.find_or_create_by!(name: "Hågat")
    supporter = Supporter.create!(
      first_name: "Pending",
      last_name: "Intake",
      contact_number: "+16715557666",
      village: village,
      source: "public_signup",
      attribution_method: "public_signup",
      contact_classification: "new_intake",
      review_status: "pending",
      status: "active"
    )

    assert_no_difference -> { SupporterContactAttempt.count } do
      patch "/api/v1/supporters/#{supporter.id}/canvass_update",
        params: {
          canvass_update: {
            contact_classification: "active_contact",
            support_status: "supporter",
            contact_attempt: {
              channel: "in_person",
              outcome: "reached"
            }
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :conflict
    supporter.reload
    assert_equal "new_intake", supporter.contact_classification
    assert_equal "pending", supporter.review_status
    assert_equal "unknown", supporter.support_status
    assert_equal "not_household_canvassable", response.parsed_body["code"]
  end

  test "canvass update rolls back classification if contact attempt is invalid" do
    village = Village.find_or_create_by!(name: "Malesso")
    supporter = Supporter.create!(
      first_name: "Rollback",
      last_name: "Check",
      contact_number: "+16715557777",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      review_status: "approved",
      status: "active"
    )

    assert_no_difference -> { SupporterContactAttempt.count } do
      patch "/api/v1/supporters/#{supporter.id}/canvass_update",
        params: {
          canvass_update: {
            contact_classification: "active_contact",
            support_status: "supporter",
            contact_attempt: {
              channel: "in_person",
              outcome: "maybe"
            }
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "active_contact", supporter.reload.contact_classification
    assert_equal "unknown", supporter.support_status
  end

  test "canvass update requires contact attempt details" do
    village = Village.find_or_create_by!(name: "Mongmong-Toto-Maite")
    supporter = Supporter.create!(
      first_name: "Missing",
      last_name: "Attempt",
      contact_number: "+16715558888",
      village: village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "active_contact",
      review_status: "approved",
      status: "active"
    )

    assert_no_difference -> { SupporterContactAttempt.count } do
      patch "/api/v1/supporters/#{supporter.id}/canvass_update",
        params: {
          canvass_update: {
            contact_classification: "active_contact",
            support_status: "supporter"
          }
        },
        headers: auth_headers(@admin),
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "unknown", supporter.reload.support_status
    assert_equal "contact_attempt_required", response.parsed_body["code"]
  end
end
