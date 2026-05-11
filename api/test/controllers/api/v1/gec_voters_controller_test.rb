require "test_helper"

class Api::V1::GecVotersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @precinct = Precinct.find_or_create_by!(village: @village, number: "15A") do |precinct|
      precinct.alpha_range = "A-Z"
    end
    @admin = User.create!(
      clerk_id: "clerk-gec-admin-#{SecureRandom.hex(4)}",
      email: "gec-admin-#{SecureRandom.hex(4)}@example.com",
      name: "GEC Admin",
      role: "campaign_admin"
    )
    @leader = User.create!(
      clerk_id: "clerk-gec-leader-#{SecureRandom.hex(4)}",
      email: "gec-leader-#{SecureRandom.hex(4)}@example.com",
      name: "GEC Leader",
      role: "block_leader",
      assigned_village_id: @village.id
    )
    @voter = GecVoter.create!(
      first_name: "Juan",
      middle_name: "Santos",
      last_name: "Cruz",
      birth_year: 1980,
      address: "123 Chalan Santo Papa",
      village: @village,
      village_name: @village.name,
      precinct: @precinct,
      precinct_number: @precinct.number,
      voter_registration_number: "GEC-123",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
  end

  test "index searches GEC voters by name and address" do
    get "/api/v1/gec_voters", params: { q: "Juan Santo" }, headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @voter.id, payload["gec_voters"].first["id"]

    get "/api/v1/gec_voters", params: { q: "Chalan Santo" }, headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @voter.id, payload["gec_voters"].first["id"]
  end

  test "households groups GEC voters and DPG contacts at an address" do
    Supporter.create!(
      first_name: "Maria",
      last_name: "Cruz",
      contact_number: "671-555-0101",
      village: @village,
      street_address: @voter.address,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )

    get "/api/v1/gec_voters/households", params: { q: "123 Chalan" }, headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    household = payload["households"].first
    assert_equal @voter.address, household["address"]
    assert_equal 1, household["gec_voters"].length
    assert_equal 1, household["contacts"].length
  end

  test "admin can create a DPG contact from a GEC voter" do
    assert_difference -> { Supporter.count }, 1 do
      post "/api/v1/gec_voters/#{@voter.id}/create_contact", headers: auth_headers(@admin)
    end

    assert_response :created
    contact = Supporter.find(JSON.parse(response.body).dig("supporter", "id"))
    assert_equal @voter.id, contact.gec_voter_id
    assert_equal "active_contact", contact.contact_classification
    assert_equal "verified", contact.verification_status
    assert_equal "yes", contact.registered_voter_status
  end

  test "link contact audit log records previous GEC voter id when relinking" do
    previous_voter = GecVoter.create!(
      first_name: "Old",
      last_name: "Match",
      village: @village,
      village_name: @village.name,
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    contact = Supporter.create!(
      first_name: "Relink",
      last_name: "Contact",
      contact_number: "671-555-0404",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )
    contact.update!(gec_voter: previous_voter)

    post "/api/v1/gec_voters/#{@voter.id}/link_contact",
      params: { supporter_id: contact.id },
      headers: auth_headers(@admin),
      as: :json

    assert_response :success
    assert_equal @voter.id, contact.reload.gec_voter_id
    audit_log = AuditLog.where(auditable: contact, action: "linked_to_gec_voter").order(:created_at).last
    assert_equal previous_voter.id, audit_log.changed_data.dig("gec_voter_id", 0)
    assert_equal @voter.id, audit_log.changed_data.dig("gec_voter_id", 1)
  end

  test "stats respects village scoping for removed voters and linked contacts" do
    other_village = Village.find_or_create_by!(name: "Dededo")
    other_voter = GecVoter.create!(
      first_name: "Pedro",
      last_name: "Santos",
      address: "999 Marine Corps Drive",
      village: other_village,
      village_name: other_village.name,
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    GecVoter.create!(
      first_name: "Removed",
      last_name: "Barrigada",
      village: @village,
      village_name: @village.name,
      status: "removed",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    GecVoter.create!(
      first_name: "Removed",
      last_name: "Dededo",
      village: other_village,
      village_name: other_village.name,
      status: "removed",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    barrigada_contact = Supporter.create!(
      first_name: "Linked",
      last_name: "Barrigada",
      contact_number: "671-555-0202",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )
    barrigada_contact.update!(gec_voter: @voter)
    dededo_contact = Supporter.create!(
      first_name: "Linked",
      last_name: "Dededo",
      contact_number: "671-555-0303",
      village: other_village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )
    dededo_contact.update!(gec_voter: other_voter)

    get "/api/v1/gec_voters/stats", headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["removed_voters"]
    assert_equal 1, payload["linked_contacts"]
    assert_equal [ "Barrigada" ], payload["villages"].map { |row| row["name"] }
  end

  test "only data ops can view GEC imports" do
    get "/api/v1/gec_voters/imports", headers: auth_headers(@leader)

    assert_response :forbidden
    assert_equal "gec_import_access_required", JSON.parse(response.body)["code"]

    get "/api/v1/gec_voters/imports", headers: auth_headers(@admin)

    assert_response :success
  end

  test "activate import audit log records actual previous active state" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec-voters.csv",
      status: "completed",
      import_type: "full_list",
      active_election_day: true
    )

    post "/api/v1/gec_voters/imports/#{import.id}/activate", headers: auth_headers(@admin)

    assert_response :success
    audit_log = AuditLog.where(auditable: import, action: "gec_import_activated").order(:created_at).last
    assert_equal true, audit_log.changed_data.dig("active_election_day", 0)
    assert_equal true, audit_log.changed_data.dig("active_election_day", 1)
  end
end
