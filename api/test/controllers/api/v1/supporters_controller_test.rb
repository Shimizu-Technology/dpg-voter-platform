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
end
