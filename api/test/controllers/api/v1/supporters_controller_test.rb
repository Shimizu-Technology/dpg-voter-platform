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

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "verified" },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    supporter.reload
    assert_equal gec_voter.id, supporter.gec_voter_id
    assert_equal gec_village.id, supporter.village_id
    assert_equal submitted_village.id, supporter.submitted_village_id
    assert_equal gec_precinct.id, supporter.precinct_id
    assert_equal true, supporter.registered_voter
    assert_equal "yes", supporter.registered_voter_status
    assert_equal "manual_staff_verified", supporter.verification_reason
    assert_equal "Leon", supporter.first_name
    assert_nil supporter.middle_name
    assert_equal "Shimizu", supporter.last_name
    assert_equal "221 Lirio Ave", supporter.street_address
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
          note: "Test submission."
        }
      },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    supporter.reload
    assert_equal "invalid", supporter.contact_classification
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
    assert_equal original_classified_at.to_i, supporter.classified_at.to_i
    assert_equal @admin.id, supporter.classified_by_user_id
    assert_equal "in_person", supporter.supporter_contact_attempts.last.channel
    assert_equal "household_canvass_logged", AuditLog.where(auditable: supporter).last.action
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
