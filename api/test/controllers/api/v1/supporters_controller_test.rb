require "test_helper"

class Api::V1::SupportersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @village = Village.create!(name: "Supporter Village")
    @user = User.create!(
      clerk_id: "clerk-supporters",
      email: "supporters@example.com",
      name: "Supporters User",
      role: "district_coordinator"
    )
    @data_team = User.create!(
      clerk_id: "clerk-data-team",
      email: "data-team@example.com",
      name: "Data Team User",
      role: "data_team"
    )
    @readonly_user = User.create!(
      clerk_id: "clerk-readonly",
      email: "readonly@example.com",
      name: "Read Only User",
      role: "block_leader",
      assigned_village_id: @village.id
    )
    @poll_watcher = User.create!(
      clerk_id: "clerk-poll-watcher",
      email: "pollwatcher@example.com",
      name: "Poll Watcher User",
      role: "poll_watcher"
    )

    250.times do |idx|
      Supporter.create!(
        first_name: "Supporter", last_name: "#{idx}", print_name: "Supporter #{idx}",
        contact_number: "671555#{format('%04d', idx)}",
        village: @village,
        source: "staff_entry",
        status: "active",
        registered_voter: false,
        yard_sign: false,
        motorcade_available: false
      )
    end
  end

  test "index requires authentication" do
    get "/api/v1/supporters"
    assert_response :unauthorized
    payload = JSON.parse(response.body)
    assert_equal "authorization_token_required", payload["code"]
  end

  test "poll watcher cannot view supporters index" do
    get "/api/v1/supporters", headers: auth_headers(@poll_watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "supporter_access_required", payload["code"]
  end

  test "index clamps per_page to max allowed" do
    get "/api/v1/supporters",
      params: { per_page: 10_000, page: 1 },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 200, payload.dig("pagination", "per_page")
    assert_equal 200, payload["supporters"].size
  end

  test "index derives flagged reason label and detail for legacy supporter without persisted reason" do
    GecVoter.create!(
      first_name: "Legacy",
      last_name: "IndexFlagged",
      birth_year: 1982,
      village_name: @village.name,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )
    GecVoter.create!(
      first_name: "Legacy",
      last_name: "IndexFlagged",
      birth_year: 1982,
      village_name: @village.name,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )

    supporter = Supporter.create!(
      first_name: "Legacy",
      last_name: "IndexFlagged",
      print_name: "Legacy IndexFlagged",
      dob: Date.new(1982, 4, 1),
      contact_number: "6715559333",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(verification_reason: nil, verification_reason_metadata: {})

    get "/api/v1/supporters",
      params: { search: "IndexFlagged" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter_payload = payload.fetch("supporters").find { |item| item["id"] == supporter.id }

    assert_equal "multiple_matches", supporter_payload["verification_reason"]
    assert_equal "Multiple Matches", supporter_payload["verification_reason_label"]
    assert_match(/2 possible GEC matches/, supporter_payload["verification_reason_detail"])
  end

  test "index exposes current GEC match separately from registered voter status" do
    matched_voter = GecVoter.create!(
      first_name: "Matched",
      last_name: "Supporter",
      village_name: @village.name,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )

    matched_supporter = Supporter.create!(
      first_name: "Matched",
      last_name: "Supporter",
      print_name: "Matched Supporter",
      contact_number: "6715559444",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "verified",
      registered_voter: true,
      gec_voter: matched_voter
    )
    matched_supporter.update_columns(
      gec_voter_id: matched_voter.id,
      verification_status: "verified",
      registered_voter: true
    )

    flagged_supporter = Supporter.create!(
      first_name: "Flagged",
      last_name: "Supporter",
      print_name: "Flagged Supporter",
      contact_number: "6715559555",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "village_mismatch",
      verification_reason_metadata: { "gec_village_name" => "Other Village" }
    )
    flagged_supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "village_mismatch"
    )

    get "/api/v1/supporters",
      params: { search: "Supporter" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    matched_payload = payload.fetch("supporters").find { |item| item["id"] == matched_supporter.id }
    flagged_payload = payload.fetch("supporters").find { |item| item["id"] == flagged_supporter.id }

    assert_equal true, matched_payload["registered_voter"]
    assert_equal true, matched_payload["current_gec_match"]
    assert_equal true, flagged_payload["registered_voter"]
    assert_equal false, flagged_payload["current_gec_match"]
  end

  test "index keeps verified but unlinked supporters out of current GEC match bucket" do
    verified_unlinked = Supporter.create!(
      first_name: "Verified",
      last_name: "Unlinked",
      print_name: "Verified Unlinked",
      contact_number: "6715559666",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )
    verified_unlinked.update_columns(
      gec_voter_id: nil,
      verification_status: "verified",
      registered_voter: true
    )

    get "/api/v1/supporters",
      params: { search: "6715559666" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter_payload = payload.fetch("supporters").find { |item| item["id"] == verified_unlinked.id }

    assert_equal true, supporter_payload["registered_voter"]
    assert_equal false, supporter_payload["current_gec_match"]
  end

  test "index batches legacy flagged reason lookups per page" do
    supporters = 2.times.map do |i|
      Supporter.create!(
        first_name: "Legacy",
        last_name: "Batch#{i}",
        print_name: "Legacy Batch#{i}",
        dob: Date.new(1982, 4, i + 1),
        contact_number: "67155593#{40 + i}",
        village: @village,
        source: "staff_entry",
        status: "active",
        verification_status: "flagged",
        registered_voter: true
      ).tap do |supporter|
        supporter.update_columns(
          verification_status: "flagged",
          registered_voter: true,
          verification_reason: nil,
          verification_reason_metadata: {}
        )
      end
    end

    batch_calls = []
    village_name = @village.name
    original_batch_lookup = GecVoter.method(:find_matches_for_supporters)
    GecVoter.define_singleton_method(:find_matches_for_supporters) do |batch_supporters|
      batch_calls << batch_supporters.map(&:id)
      batch_supporters.index_by(&:id).transform_values do
        [ {
          gec_voter: GecVoter.new(village_name: village_name),
          confidence: :medium,
          match_type: :fuzzy_name_year,
          match_count: 1
        } ]
      end
    end

    begin
      get "/api/v1/supporters",
        params: { search: "Legacy" },
        headers: auth_headers(@user)
    ensure
      GecVoter.define_singleton_method(:find_matches_for_supporters, original_batch_lookup)
    end

    assert_response :success
    assert_equal [ supporters.map(&:id).sort ], batch_calls.map(&:sort)
    payload = JSON.parse(response.body)
    returned_reasons = payload.fetch("supporters")
      .select { |item| supporters.map(&:id).include?(item["id"]) }
      .map { |item| item["verification_reason"] }
    assert_equal [ "fuzzy_name_match", "fuzzy_name_match" ], returned_reasons.sort
  end

  test "district coordinator cannot access duplicates review" do
    get "/api/v1/supporters/duplicates", headers: auth_headers(@user)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "data_ops_access_required", payload["code"]
  end

  test "data team can access duplicates review" do
    get "/api/v1/supporters/duplicates", headers: auth_headers(@data_team)

    assert_response :success
  end

  test "create auto-assigns precinct when village has one precinct" do
    single_village = Village.create!(name: "Single Precinct Village")
    single_precinct = Precinct.create!(number: "SP-1", village: single_village, registered_voters: 100)

    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Single", last_name: "Precinct Supporter", print_name: "Single Precinct Supporter",
          contact_number: "6715557000",
          village_id: single_village.id,
          precinct_id: nil,
          registered_voter: true
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal single_precinct.id, payload.dig("supporter", "precinct_id")
  end

  test "create rejects more than the household submission limit" do
    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Primary",
          last_name: "Too Many",
          print_name: "Primary Too Many",
          contact_number: "6715557010",
          village_id: @village.id,
          registered_voter: false,
          household_members: 9.times.map do |index|
            {
              first_name: "Member#{index + 1}",
              last_name: "Too Many",
              registered_voter_status: "not_sure"
            }
          end
        }
      }

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_includes payload["errors"], "You can add up to 8 household supporters per submission"
  end

  test "authenticated user can assign supporter precinct" do
    target_precinct = Precinct.create!(number: "SP-2", village: @village, registered_voters: 100)
    supporter = Supporter.create!(
      first_name: "Needs", last_name: "Assignment", print_name: "Needs Assignment",
      contact_number: "6715557001",
      village: @village,
      precinct: nil,
      source: "staff_entry",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}",
      params: { supporter: { precinct_id: target_precinct.id } },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal target_precinct.id, payload.dig("supporter", "precinct_id")
  end

  test "changing village reassigns precinct when no precinct is provided" do
    single_village = Village.create!(name: "Village Reassign Test")
    single_precinct = Precinct.create!(number: "SP-4", village: single_village, registered_voters: 100)
    supporter = Supporter.create!(
      first_name: "Village", last_name: "Mover", print_name: "Village Mover",
      contact_number: "6715557004",
      village: @village,
      precinct: @precinct,
      source: "staff_entry",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}",
      params: { supporter: { village_id: single_village.id } },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal single_village.id, payload.dig("supporter", "village_id")
    assert_equal single_precinct.id, payload.dig("supporter", "precinct_id")
  end

  test "public create sets source to public_signup without auth header" do
    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Public", last_name: "Signup", print_name: "Public Signup",
          contact_number: "6715558000",
          village_id: @village.id,
          registered_voter: true
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "public_signup", payload.dig("supporter", "source")
    assert_equal "public_signup", payload.dig("supporter", "attribution_method")
    assert_equal "pending_public_review", payload.dig("supporter", "intake_status")
    assert_equal "pending", payload.dig("supporter", "public_review_status")
    assert_equal "pending", payload.dig("supporter", "review_status")
    assert_equal true, payload.dig("supporter", "self_reported_registered_voter")
  end

  test "public create links supporter to referral code when leader code is present" do
    referral = ReferralCode.create!(
      code: "AB-CHA-1234",
      display_name: "Alyssa Blas",
      village: @village
    )

    post "/api/v1/supporters?leader_code=#{referral.code}",
      params: {
        supporter: {
          first_name: "Referred", last_name: "Signup", print_name: "Referred Signup",
          contact_number: "6715558002",
          village_id: @village.id,
          registered_voter: true
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal referral.code, payload.dig("supporter", "leader_code")
    assert_equal referral.id, payload.dig("supporter", "referral_code_id")
    assert_equal "Alyssa Blas", payload.dig("supporter", "referral_display_name")
    assert_equal "qr_self_signup", payload.dig("supporter", "attribution_method")
  end

  test "public create persists Becky intake fields" do
    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Becky",
          last_name: "Supporter",
          print_name: "Supporter, Becky",
          contact_number: "6715558015",
          village_id: @village.id,
          registered_voter_status: "not_sure",
          needs_voter_registration_help: true,
          needs_absentee_ballot_help: true,
          needs_election_day_ride: true,
          wants_to_volunteer: true,
          referred_by_name: "Neighbor Nora"
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    supporter = Supporter.find(payload.dig("supporter", "id"))

    assert_equal "not_sure", payload.dig("supporter", "registered_voter_status")
    assert_nil payload.dig("supporter", "self_reported_registered_voter")
    assert_equal true, payload.dig("supporter", "needs_voter_registration_help")
    assert_equal true, payload.dig("supporter", "needs_absentee_ballot_help")
    assert_equal true, payload.dig("supporter", "needs_election_day_ride")
    assert_equal true, payload.dig("supporter", "wants_to_volunteer")
    assert_equal "Neighbor Nora", payload.dig("supporter", "referred_by_name")
    assert_equal "not_sure", supporter.registered_voter_status
    assert_equal true, supporter.needs_voter_registration_help
    assert_equal true, supporter.needs_absentee_ballot_help
    assert_equal true, supporter.needs_election_day_ride
    assert_equal true, supporter.wants_to_volunteer
    assert_equal "Neighbor Nora", supporter.referred_by_name
  end

  test "public create can create linked household supporters" do
    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Primary",
          last_name: "Household",
          print_name: "Household, Primary",
          contact_number: "6715558016",
          email: "primary@example.com",
          street_address: "123 Marine Corps Dr",
          village_id: @village.id,
          registered_voter_status: "yes",
          household_members: [
            {
              first_name: "Second",
              last_name: "Household",
              registered_voter_status: "no",
              needs_voter_registration_help: true
            }
          ]
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    primary = Supporter.find(payload.dig("supporter", "id"))
    household_members = Supporter.where(household_group_id: primary.household_group_id).order(:id)

    assert_equal 1, payload["household_supporters_created"]
    assert primary.household_group_id.present?
    assert_equal 2, household_members.count
    assert_equal [ true, false ], household_members.map(&:household_primary)
    assert_equal [ "yes", "no" ], household_members.map(&:registered_voter_status)
    assert_equal [ "6715558016", "6715558016" ], household_members.map(&:contact_number)
    assert_equal [ "primary@example.com", "primary@example.com" ], household_members.map(&:email)
    assert_equal true, household_members.last.needs_voter_registration_help
  end

  test "public create returns validation-style error when household group creation hits a db constraint failure" do
    controller_class = Api::V1::SupportersController
    original_build_household_group = controller_class.instance_method(:build_household_group)

    controller_class.define_method(:build_household_group) do |_primary_attributes, _household_members|
      raise ActiveRecord::StatementInvalid, "constraint failure"
    end

    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Primary",
          last_name: "Constraint",
          print_name: "Constraint, Primary",
          contact_number: "6715558018",
          village_id: @village.id,
          registered_voter_status: "yes",
          household_members: [
            {
              first_name: "Second",
              last_name: "Constraint",
              registered_voter_status: "no"
            }
          ]
        }
      }

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_includes payload["errors"], "Could not save this household signup. Please review the submission and try again."
  ensure
    controller_class.define_method(:build_household_group, original_build_household_group)
  end

  test "outreach status registered does not mark supporter as GEC found" do
    supporter = Supporter.create!(
      first_name: "Outreach",
      last_name: "Registered",
      print_name: "Registered, Outreach",
      contact_number: "6715558017",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no"
    )

    patch "/api/v1/supporters/#{supporter.id}/outreach_status",
      params: { registration_outreach_status: "registered" },
      headers: auth_headers(@user)

    assert_response :success
    supporter.reload
    assert_equal "registered", supporter.registration_outreach_status
    assert_equal false, supporter.registered_voter
  end

  test "outreach status can be reset back to not contacted" do
    supporter = Supporter.create!(
      first_name: "Outreach",
      last_name: "Reset",
      print_name: "Reset, Outreach",
      contact_number: "67155580171",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no",
      registration_outreach_status: "contacted",
      registration_outreach_date: Time.current,
      registration_outreach_notes: "Left voicemail"
    )

    patch "/api/v1/supporters/#{supporter.id}/outreach_status",
      params: { registration_outreach_status: nil },
      headers: auth_headers(@user)

    assert_response :success
    supporter.reload
    assert_nil supporter.registration_outreach_status
    assert_nil supporter.registration_outreach_date
    assert_equal "Left voicemail", supporter.registration_outreach_notes
  end

  test "support follow-up status can be updated independently" do
    supporter = Supporter.create!(
      first_name: "Support",
      last_name: "Workflow",
      print_name: "Workflow, Support",
      contact_number: "67155580172",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: true,
      registered_voter_status: "yes",
      needs_absentee_ballot_help: true
    )

    patch "/api/v1/supporters/#{supporter.id}/outreach_status",
      params: { support_follow_up_status: "completed", support_follow_up_notes: "Ride arranged" },
      headers: auth_headers(@user)

    assert_response :success
    supporter.reload
    assert_equal "completed", supporter.support_follow_up_status
    assert_equal "Ride arranged", supporter.support_follow_up_notes
    assert_not_nil supporter.support_follow_up_date
    assert_nil supporter.registration_outreach_status
  end

  test "partial supporter update preserves Becky voter status fields when none are submitted" do
    supporter = Supporter.create!(
      first_name: "Preserve",
      last_name: "VoterStatus",
      print_name: "VoterStatus, Preserve",
      contact_number: "6715558022",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: true,
      registered_voter_status: "yes",
      self_reported_registered_voter: true
    )

    patch "/api/v1/supporters/#{supporter.id}",
      params: { supporter: { first_name: "Updated" } },
      headers: auth_headers(@user)

    assert_response :success
    supporter.reload
    assert_equal "Updated", supporter.first_name
    assert_equal "yes", supporter.registered_voter_status
    assert_equal true, supporter.self_reported_registered_voter
  end

  test "outreach returns Becky queue metadata and prioritizes registration follow-up" do
    high_priority = Supporter.create!(
      first_name: "Queue",
      last_name: "HighPriority",
      print_name: "HighPriority, Queue",
      contact_number: "6715558018",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no",
      needs_voter_registration_help: true
    )
    contacted = Supporter.create!(
      first_name: "Queue",
      last_name: "Contacted",
      print_name: "Contacted, Queue",
      contact_number: "6715558019",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: true,
      registered_voter_status: "yes",
      wants_to_volunteer: true,
      registration_outreach_status: "contacted",
      registration_outreach_notes: "Left voicemail"
    )

    get "/api/v1/supporters/outreach",
      params: { search: "Queue" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    returned_ids = payload.fetch("supporters").map { |supporter| supporter["id"] }

    assert_equal [ high_priority.id, contacted.id ], returned_ids.first(2)
    assert_equal "Registration Priority", payload["supporters"].first["follow_up_priority"]
    assert_includes payload["supporters"].first["follow_up_reasons"], "Needs registration help"
    assert_equal true, payload["supporters"].first["follow_up_open"]
    assert_equal true, payload["counts"]["registration_priority"] >= 1
    assert_equal true, payload["counts"]["open"] >= 2
  end

  test "outreach queue_view filters to registered follow-up records" do
    Supporter.create!(
      first_name: "Queue",
      last_name: "RegisteredOnly",
      print_name: "RegisteredOnly, Queue",
      contact_number: "6715558020",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no",
      registration_outreach_status: "registered"
    )
    Supporter.create!(
      first_name: "Queue",
      last_name: "StillOpen",
      print_name: "StillOpen, Queue",
      contact_number: "6715558021",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no"
    )

    get "/api/v1/supporters/outreach",
      params: { search: "Queue", queue_view: "registered_follow_up" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["supporters"].length
    assert_equal "RegisteredOnly", payload["supporters"].first["last_name"]
    assert_equal "Resolved", payload["supporters"].first["follow_up_priority"]
    assert_includes payload["supporters"].first["follow_up_reasons"], "Registered via follow-up"
  end

  test "outreach keeps support requests open after registration follow-up is resolved" do
    mixed_supporter = Supporter.create!(
      first_name: "Queue",
      last_name: "MixedOpen",
      print_name: "MixedOpen, Queue",
      contact_number: "6715558023",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      registered_voter: false,
      registered_voter_status: "no",
      needs_absentee_ballot_help: true,
      registration_outreach_status: "registered"
    )

    get "/api/v1/supporters/outreach",
      params: { search: "Queue", queue_view: "open" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    mixed_row = payload.fetch("supporters").find { |supporter| supporter["id"] == mixed_supporter.id }

    assert_not_nil mixed_row
    assert_equal true, mixed_row["support_follow_up_open"]
    assert_equal false, mixed_row["registration_follow_up_open"]
    assert_equal "Support Help", mixed_row["follow_up_priority"]

    get "/api/v1/supporters/outreach",
      params: { search: "Queue", queue_view: "completed" },
      headers: auth_headers(@user)

    assert_response :success
    completed_payload = JSON.parse(response.body)
    completed_ids = completed_payload.fetch("supporters").map { |supporter| supporter["id"] }

    assert_not_includes completed_ids, mixed_supporter.id
  end

  test "public create ignores crafted submitted village id" do
    other_village = Village.create!(name: "Other Submission Village")

    post "/api/v1/supporters",
      params: {
        supporter: {
          first_name: "Public", last_name: "Spoof", print_name: "Public Spoof",
          contact_number: "6715558003",
          village_id: @village.id,
          submitted_village_id: other_village.id,
          registered_voter: true
        }
      }

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal @village.id, payload.dig("supporter", "submitted_village_id")
  end

  test "create with staff entry mode sets source to staff_entry and entered_by user" do
    staff_user = User.create!(
      clerk_id: "clerk-staff-entry",
      email: "staff-entry@example.com",
      name: "Staff Entry User",
      role: "block_leader",
      assigned_village_id: @village.id
    )

    post "/api/v1/supporters?entry_mode=staff",
      params: {
        supporter: {
          first_name: "Staff", last_name: "Signup", print_name: "Staff Signup",
          contact_number: "6715558001",
          village_id: @village.id,
          registered_voter: true
        }
      },
      headers: auth_headers(staff_user)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "staff_entry", payload.dig("supporter", "source")
    assert_equal "staff_manual", payload.dig("supporter", "attribution_method")
    assert_equal @village.id, payload.dig("supporter", "submitted_village_id")
    assert_equal "accepted", payload.dig("supporter", "intake_status")
    assert_equal "not_applicable", payload.dig("supporter", "public_review_status")
    assert_equal "pending", payload.dig("supporter", "review_status")
    assert_equal true, payload.dig("supporter", "self_reported_registered_voter")
    assert_equal staff_user.id, Supporter.find(payload.dig("supporter", "id")).entered_by_user_id
  end

  test "create with staff entry mode persists Becky intake fields" do
    staff_user = User.create!(
      clerk_id: "clerk-staff-becky",
      email: "staff-becky@example.com",
      name: "Staff Becky User",
      role: "block_leader",
      assigned_village_id: @village.id
    )

    post "/api/v1/supporters?entry_mode=staff",
      params: {
        supporter: {
          first_name: "Staff",
          last_name: "Becky",
          print_name: "Becky, Staff",
          contact_number: "6715558002",
          village_id: @village.id,
          registered_voter_status: "yes",
          registered_voter_location_note: "Barrigada precinct",
          referred_by_name: "Neighbor Nora",
          wants_to_volunteer: true,
          needs_absentee_ballot_help: true,
          needs_homebound_voting_help: false,
          needs_voter_registration_help: true,
          needs_election_day_ride: true
        }
      },
      headers: auth_headers(staff_user)

    assert_response :created
    payload = JSON.parse(response.body)
    supporter = Supporter.find(payload.dig("supporter", "id"))

    assert_equal "yes", supporter.registered_voter_status
    assert_equal true, supporter.self_reported_registered_voter
    assert_equal "Barrigada precinct", supporter.registered_voter_location_note
    assert_equal "Neighbor Nora", supporter.referred_by_name
    assert_equal true, supporter.wants_to_volunteer
    assert_equal true, supporter.needs_absentee_ballot_help
    assert_equal true, supporter.needs_voter_registration_help
    assert_equal true, supporter.needs_election_day_ride
  end

  test "accepting public signup preserves origin and marks supporter accepted" do
    supporter = Supporter.create!(
      first_name: "Marissa", last_name: "Public", print_name: "Public, Marissa",
      contact_number: "6715558123",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "pending_public_review",
      status: "active",
      verification_status: "unverified",
      self_reported_registered_voter: true,
      registered_voter: false
    )

    patch "/api/v1/supporters/#{supporter.id}/accept_to_quota", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter.reload

    assert_equal "public_signup", supporter.source
    assert_equal "accepted", supporter.intake_status
    assert_equal "approved", supporter.public_review_status
    assert_equal "pending", supporter.review_status
    assert_equal "public_signup", payload.dig("supporter", "source")
    assert_equal "accepted", payload.dig("supporter", "intake_status")
    assert_equal "approved", payload.dig("supporter", "public_review_status")
    assert_equal "pending", payload.dig("supporter", "review_status")

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@data_team)

    assert_response :success
    detail_payload = JSON.parse(response.body)
    accepted_log = detail_payload.fetch("audit_logs").find { |log| log.fetch("action") == "accepted_to_quota" }
    assert accepted_log.present?
    assert_equal "Sent to supporter review", accepted_log.fetch("action_label")
  end

  test "public review only shows pending self signups" do
    pending = Supporter.create!(
      first_name: "Pending", last_name: "Public", print_name: "Public, Pending",
      contact_number: "6715558124",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "pending_public_review",
      status: "active",
      verification_status: "unverified",
      self_reported_registered_voter: true,
      registered_voter: false
    )
    accepted = Supporter.create!(
      first_name: "Accepted", last_name: "Public", print_name: "Public, Accepted",
      contact_number: "6715558125",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      status: "active",
      verification_status: "unverified",
      registered_voter: false
    )

    get "/api/v1/supporters/public_review", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    ids = payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }
    pending_payload = payload.fetch("supporters").find { |supporter_payload| supporter_payload.fetch("id") == pending.id }

    assert_includes ids, pending.id
    assert_not_includes ids, accepted.id
    assert_equal true, pending_payload.fetch("self_reported_registered_voter")
    assert_equal 1, payload.dig("summary", "pending_review")
    assert_equal 1, payload.dig("summary", "accepted")
  end

  test "public review can show approved and rejected public submissions" do
    approved = Supporter.create!(
      first_name: "Approved", last_name: "Public", print_name: "Public, Approved Two",
      contact_number: "6715558127",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      status: "active",
      public_review_status: "approved",
      review_status: "pending",
      verification_status: "unverified",
      self_reported_registered_voter: true,
      registered_voter: false
    )
    rejected = Supporter.create!(
      first_name: "Rejected", last_name: "Public", print_name: "Public, Rejected Two",
      contact_number: "6715558128",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "pending_public_review",
      status: "active",
      public_review_status: "rejected",
      review_status: "rejected",
      verification_status: "unverified",
      self_reported_registered_voter: false,
      registered_voter: false
    )

    get "/api/v1/supporters/public_review", params: { review_bucket: "approved" }, headers: auth_headers(@data_team)
    assert_response :success
    approved_payload = JSON.parse(response.body)
    approved_ids = approved_payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }

    assert_equal "approved", approved_payload.fetch("current_bucket")
    assert_includes approved_ids, approved.id
    assert_not_includes approved_ids, rejected.id

    get "/api/v1/supporters/public_review", params: { review_bucket: "rejected" }, headers: auth_headers(@data_team)
    assert_response :success
    rejected_payload = JSON.parse(response.body)
    rejected_ids = rejected_payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }

    assert_equal "rejected", rejected_payload.fetch("current_bucket")
    assert_includes rejected_ids, rejected.id
    assert_not_includes rejected_ids, approved.id
  end

  test "rejecting public signup keeps record but removes it from pending public review" do
    supporter = Supporter.create!(
      first_name: "Rejected", last_name: "Public", print_name: "Public, Rejected",
      contact_number: "6715558126",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "pending_public_review",
      status: "active",
      verification_status: "unverified",
      self_reported_registered_voter: false,
      registered_voter: false
    )

    patch "/api/v1/supporters/#{supporter.id}/reject_public_review", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter.reload

    assert_equal "rejected", supporter.public_review_status
    assert_equal "rejected", supporter.review_status
    assert_equal "rejected", payload.dig("supporter", "public_review_status")
    assert_equal "rejected", payload.dig("supporter", "review_status")

    get "/api/v1/supporters/public_review", headers: auth_headers(@data_team)
    assert_response :success
    public_review_payload = JSON.parse(response.body)
    ids = public_review_payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }

    assert_not_includes ids, supporter.id
    assert_equal 0, public_review_payload.dig("summary", "pending_review")
    assert_equal 1, public_review_payload.dig("summary", "rejected")
  end

  test "create with staff scan entry mode sets scan attribution" do
    staff_user = User.create!(
      clerk_id: "clerk-staff-scan",
      email: "staff-scan@example.com",
      name: "Staff Scan User",
      role: "block_leader",
      assigned_village_id: @village.id
    )

    post "/api/v1/supporters?entry_mode=staff&entry_channel=scan",
      params: {
        supporter: {
          first_name: "Scan", last_name: "Signup", print_name: "Scan Signup",
          contact_number: "6715558003",
          village_id: @village.id,
          registered_voter: true
        }
      },
      headers: auth_headers(staff_user)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "staff_scan", payload.dig("supporter", "attribution_method")
  end

  test "create keeps duplicates active while flagging duplicate review" do
    Supporter.create!(
      first_name: "Talia", last_name: "Example", print_name: "Example, Talia",
      contact_number: "6715558010",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified"
    )

    post "/api/v1/supporters?entry_mode=staff",
      params: {
        supporter: {
          first_name: "Talia", last_name: "Example", print_name: "Example, Talia",
          contact_number: "6715558011",
          village_id: @village.id,
          registered_voter: true
        }
      },
      headers: auth_headers(@user)

    assert_response :created
    payload = JSON.parse(response.body)
    created = Supporter.find(payload.dig("supporter", "id"))

    assert_equal true, payload["duplicate_warning"]
    assert_equal "active", created.status
    assert_equal true, created.potential_duplicate
    assert_equal "active", payload.dig("supporter", "status")
  end

  test "index can filter by precinct and unassigned precinct" do
    precinct = Precinct.create!(number: "SP-3", village: @village, alpha_range: "A-Z", registered_voters: 100)
    assigned = Supporter.create!(
      first_name: "Assigned", last_name: "Supporter", print_name: "Assigned Supporter",
      contact_number: "6715557002",
      village: @village,
      precinct: precinct,
      source: "staff_entry",
      status: "active"
    )
    # Create a village with no precincts so auto-assign leaves precinct_id nil
    no_precinct_village = Village.create!(name: "No Precinct Village", region: "Test")
    unassigned = Supporter.create!(
      first_name: "Unassigned", last_name: "Supporter", print_name: "Unassigned Supporter",
      contact_number: "6715557003",
      village: no_precinct_village,
      source: "staff_entry",
      status: "active"
    )
    # Move to target village without triggering callback
    unassigned.update_column(:village_id, @village.id)
    unassigned.update_column(:precinct_id, nil)

    get "/api/v1/supporters",
      params: { village_id: @village.id, precinct_id: precinct.id },
      headers: auth_headers(@user)
    assert_response :success
    payload = JSON.parse(response.body)
    ids = payload.fetch("supporters").map { |s| s.fetch("id") }
    assert_includes ids, assigned.id
    assert_not_includes ids, unassigned.id

    get "/api/v1/supporters",
      params: { village_id: @village.id, unassigned_precinct: "true" },
      headers: auth_headers(@user)
    assert_response :success
    payload = JSON.parse(response.body)
    ids = payload.fetch("supporters").map { |s| s.fetch("id") }
    assert_includes ids, unassigned.id
    assert_not_includes ids, assigned.id
  end

  test "index supports sorting by print_name ascending" do
    Supporter.create!(
      first_name: "Sort", last_name: "Test Zulu", print_name: "Sort Test Zulu",
      contact_number: "6715559100",
      village: @village,
      source: "staff_entry",
      status: "active"
    )
    Supporter.create!(
      first_name: "Sort", last_name: "Test Alpha", print_name: "Sort Test Alpha",
      contact_number: "6715559101",
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    get "/api/v1/supporters",
      params: { search: "Sort", sort_by: "print_name", sort_dir: "asc" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    # Filter to just our test supporters (search "Sort" may match others)
    test_names = payload.fetch("supporters")
      .map { |s| s.fetch("print_name") }
      .select { |n| n.include?("Sort") }
    # print_name is "Last, First" format from sync_print_name
    assert_equal "Test Alpha, Sort", test_names.first
    assert_equal "Test Zulu, Sort", test_names.last
  end

  test "index keeps existing filters when pipeline is public" do
    other_village = Village.create!(name: "Other Public Village", region: "Test")
    matching = Supporter.create!(
      first_name: "Public", last_name: "Alpha", print_name: "Alpha, Public",
      contact_number: "6715559102",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      public_review_status: "approved",
      review_status: "approved",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )
    wrong_village = Supporter.create!(
      first_name: "Public", last_name: "Beta", print_name: "Beta, Public",
      contact_number: "6715559103",
      village: other_village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      public_review_status: "approved",
      review_status: "approved",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )

    get "/api/v1/supporters",
      params: { pipeline: "public", village_id: @village.id, search: "Public" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    ids = payload.fetch("supporters").map { |s| s.fetch("id") }
    assert_includes ids, matching.id
    assert_not_includes ids, wrong_village.id
  end

  test "export keeps existing filters when pipeline is public" do
    other_village = Village.create!(name: "Other Export Village", region: "Test")
    in_scope = Supporter.create!(
      first_name: "Scoped", last_name: "Alpha", print_name: "Alpha, Scoped",
      contact_number: "6715559104",
      village: @village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      public_review_status: "approved",
      review_status: "approved",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )
    out_of_scope = Supporter.create!(
      first_name: "Other", last_name: "Beta", print_name: "Beta, Other",
      contact_number: "6715559105",
      village: other_village,
      source: "public_signup",
      attribution_method: "public_signup",
      intake_status: "accepted",
      public_review_status: "approved",
      review_status: "approved",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )

    get "/api/v1/supporters/export",
      params: { format_type: "csv", pipeline: "public", village_id: @village.id, search: "Scoped" },
      headers: auth_headers(@user)

    assert_response :success
    assert_includes response.body, in_scope.first_name
    assert_includes response.body, in_scope.last_name
    assert_not_includes response.body, out_of_scope.first_name
    assert_not_includes response.body, out_of_scope.last_name
  end

  test "show returns supporter details and audit logs" do
    supporter = Supporter.create!(
      first_name: "Show", last_name: "Supporter", print_name: "Show Supporter",
      contact_number: "6715559000",
      village: @village,
      source: "staff_entry",
      status: "active",
      turnout_status: "observed_elsewhere",
      turnout_note: "Observed at Precinct 15C (Barrigada).",
      turnout_updated_at: Time.current,
      turnout_updated_by_user: @poll_watcher,
      turnout_source: "poll_watcher"
    )
    AuditLog.create!(
      auditable: supporter,
      actor_user: @user,
      action: "updated",
      changed_data: { "precinct_id" => { "from" => nil, "to" => 1 } },
      metadata: {}
    )

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal supporter.id, payload.dig("supporter", "id")
    assert_equal 1, payload.fetch("audit_logs").length
    assert_equal true, payload.dig("permissions", "can_edit")
    assert_equal "district_coordinator", payload.dig("audit_logs", 0, "actor_role")
    assert_equal "Supporter updated", payload.dig("audit_logs", 0, "action_label")
    assert_equal @poll_watcher.name, payload.dig("supporter", "turnout_updated_by_user_name")
    assert_equal "observed_elsewhere", payload.dig("supporter", "turnout_status")
  end

  test "show returns household member count excluding the current supporter" do
    household_group = HouseholdGroup.create!(village: @village)
    primary = Supporter.create!(
      first_name: "Primary",
      last_name: "Counted",
      print_name: "Counted, Primary",
      contact_number: "6715559445",
      village: @village,
      source: "staff_entry",
      status: "active",
      household_group: household_group,
      household_primary: true
    )
    member = Supporter.create!(
      first_name: "Second",
      last_name: "Counted",
      print_name: "Counted, Second",
      contact_number: "6715559446",
      village: @village,
      source: "staff_entry",
      status: "active",
      household_group: household_group,
      household_primary: false
    )

    get "/api/v1/supporters/#{primary.id}", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload.dig("supporter", "household_member_count")
    assert_equal [ member.id ], payload.dig("supporter", "household_members").map { |item| item["id"] }
  end

  test "show derives flagged reason detail for legacy supporter without persisted reason" do
    GecVoter.create!(
      first_name: "Legacy",
      last_name: "Flagged",
      birth_year: 1981,
      village_name: @village.name,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )
    GecVoter.create!(
      first_name: "Legacy",
      last_name: "Flagged",
      birth_year: 1981,
      village_name: @village.name,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current,
      status: "active"
    )

    supporter = Supporter.create!(
      first_name: "Legacy",
      last_name: "Flagged",
      print_name: "Legacy Flagged",
      dob: Date.new(1981, 6, 1),
      contact_number: "6715559444",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(verification_reason: nil, verification_reason_metadata: {})

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "multiple_matches", payload.dig("supporter", "verification_reason")
    assert_match(/2 possible GEC matches/, payload.dig("supporter", "verification_reason_detail"))
    assert_equal true, payload.dig("supporter", "verification_reason_derived")
  end

  test "update creates audit log entry" do
    precinct_a = Precinct.create!(number: "SP-4A", village: @village, alpha_range: "A-L", registered_voters: 50)
    precinct_b = Precinct.create!(number: "SP-4B", village: @village, alpha_range: "M-Z", registered_voters: 50)
    supporter = Supporter.create!(
      first_name: "Audit", last_name: "Supporter", print_name: "Audit Supporter",
      contact_number: "6715559001",
      village: @village,
      source: "staff_entry",
      status: "active"
    )
    # Supporter's last name "Supporter" → auto-assigned to SP-4B (M-Z range)
    # Update to the other precinct to create a real change
    target_precinct = supporter.precinct_id == precinct_a.id ? precinct_b : precinct_a
    original_precinct_id = supporter.precinct_id

    assert_difference -> { AuditLog.count }, 1 do
      patch "/api/v1/supporters/#{supporter.id}",
        params: { supporter: { precinct_id: target_precinct.id } },
        headers: auth_headers(@user)
    end

    assert_response :success
    log = AuditLog.order(created_at: :desc).first
    assert_equal "updated", log.action
    assert_equal @user.id, log.actor_user_id
    assert_equal({ "from" => original_precinct_id, "to" => target_precinct.id }, log.changed_data["precinct_id"])
  end

  test "verify rejects marking no-gec-match supporter as verified" do
    supporter = Supporter.create!(
      first_name: "Zzxqv", last_name: "Nomatchperson", print_name: "Zzxqv Nomatchperson",
      dob: Date.new(1977, 7, 7),
      contact_number: "6715559005",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      registered_voter: false
    )
    assert_empty GecVoter.find_matches(
      first_name: supporter.first_name,
      last_name: supporter.last_name,
      dob: supporter.dob,
      birth_year: supporter.dob&.year,
      village_name: supporter.village.name
    )

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "verified" },
      headers: auth_headers(@user)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "gec_match_required_for_verified", payload["code"]

    supporter.reload
    assert_equal "unverified", supporter.verification_status
  end

  test "verify reuses match lookup when marking supporter verified" do
    supporter = Supporter.create!(
      first_name: "Verify",
      last_name: "Lookup",
      print_name: "Verify Lookup",
      dob: Date.new(1988, 8, 8),
      contact_number: "6715559008",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verified_at: nil,
      verified_by_user_id: nil
    )

    lookup_calls = 0
    village_name = @village.name
    original_find_matches = GecVoter.method(:find_matches)
    GecVoter.define_singleton_method(:find_matches) do |**|
      lookup_calls += 1
      [ {
        gec_voter: GecVoter.new(village_name: village_name),
        confidence: :exact,
        match_type: :current_gec_match,
        match_count: 1
      } ]
    end

    begin
      patch "/api/v1/supporters/#{supporter.id}/verify",
        params: { verification_status: "verified" },
        headers: auth_headers(@user)
    ensure
      GecVoter.define_singleton_method(:find_matches, original_find_matches)
    end

    assert_response :success
    assert_equal 1, lookup_calls
    assert_equal "verified", supporter.reload.verification_status
  end

  test "bulk verify rejects supporters without a current gec match" do
    GecVoter.create!(
      first_name: "Has", last_name: "Match", village_name: @village.name,
      dob: Date.new(1990, 1, 1), gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current, status: "active"
    )
    matched = Supporter.create!(
      first_name: "Has", last_name: "Match", print_name: "Has Match",
      dob: Date.new(1990, 1, 1),
      contact_number: "6715559006",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    matched.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verified_at: nil,
      verified_by_user_id: nil
    )
    no_match = Supporter.create!(
      first_name: "Qrtpl", last_name: "Nomatchbulkperson", print_name: "Qrtpl Nomatchbulkperson",
      dob: Date.new(1979, 9, 9),
      contact_number: "6715559007",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      registered_voter: false
    )
    assert_empty GecVoter.find_matches(
      first_name: no_match.first_name,
      last_name: no_match.last_name,
      dob: no_match.dob,
      birth_year: no_match.dob&.year,
      village_name: no_match.village.name
    )

    post "/api/v1/supporters/bulk_verify",
      params: { supporter_ids: [ matched.id, no_match.id ], verification_status: "verified" },
      headers: auth_headers(@user)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "gec_match_required_for_verified", payload["code"]

    assert_equal "flagged", matched.reload.verification_status
    assert_equal "unverified", no_match.reload.verification_status
  end

  test "bulk verify updates matched supporters successfully" do
    GecVoter.create!(
      first_name: "Bulk", last_name: "Verified", village_name: @village.name,
      dob: Date.new(1988, 8, 8), gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current, status: "active"
    )
    supporter = Supporter.create!(
      first_name: "Bulk", last_name: "Verified", print_name: "Bulk Verified",
      dob: Date.new(1988, 8, 8),
      contact_number: "6715559019",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verified_at: nil,
      verified_by_user_id: nil
    )

    post "/api/v1/supporters/bulk_verify",
      params: { supporter_ids: [ supporter.id ], verification_status: "verified" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["updated"]
    assert_equal "verified", payload["verification_status"]
    assert_equal "verified", supporter.reload.verification_status
    assert_equal "manual_staff_verified", supporter.verification_reason
  end

  test "bulk verify reuses each supporter's match lookup when verifying" do
    supporters = 2.times.map do |i|
      Supporter.create!(
        first_name: "Bulk#{i}",
        last_name: "Lookup",
        print_name: "Bulk#{i} Lookup",
        dob: Date.new(1988, 8, i + 1),
        contact_number: "67155591#{i + 10}",
        village: @village,
        source: "staff_entry",
        attribution_method: "staff_manual",
        status: "active",
        turnout_status: "unknown",
        verification_status: "flagged",
        registered_voter: true
      ).tap do |supporter|
        supporter.update_columns(
          verification_status: "flagged",
          registered_voter: true,
          verified_at: nil,
          verified_by_user_id: nil
        )
      end
    end

    matches = supporters.to_h do |supporter|
      [ supporter.id, [ {
        gec_voter: GecVoter.new(village_name: @village.name),
        confidence: :exact,
        match_type: :current_gec_match,
        match_count: 1
      } ] ]
    end
    lookup_calls = 0

    original_find_matches = GecVoter.method(:find_matches)
    GecVoter.define_singleton_method(:find_matches) do |first_name:, last_name:, dob:, birth_year:, village_name:|
      lookup_calls += 1
      supporter = supporters.find do |candidate|
        candidate.first_name == first_name &&
          candidate.last_name == last_name &&
          candidate.dob == dob &&
          candidate.dob&.year == birth_year &&
          candidate.village.name == village_name
      end
      matches.fetch(supporter.id)
    end

    begin
      post "/api/v1/supporters/bulk_verify",
        params: { supporter_ids: supporters.map(&:id), verification_status: "verified" },
        headers: auth_headers(@user)
    ensure
      GecVoter.define_singleton_method(:find_matches, original_find_matches)
    end

    assert_response :success
    assert_equal supporters.size, lookup_calls
    supporters.each do |supporter|
      assert_equal "verified", supporter.reload.verification_status
    end
  end

  test "manual flag stores staff review reason" do
    supporter = Supporter.create!(
      first_name: "Manual",
      last_name: "Flagged",
      print_name: "Manual Flagged",
      contact_number: "6715559020",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      registered_voter: true
    )

    patch "/api/v1/supporters/#{supporter.id}/verify",
      params: { verification_status: "flagged" },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "manual_staff_flag", payload.dig("supporter", "verification_reason")
    assert_equal "manual_staff_flag", supporter.reload.verification_reason
  end

  test "update is forbidden for non editor roles" do
    precinct = Precinct.create!(number: "SP-5", village: @village, registered_voters: 100)
    supporter = Supporter.create!(
      first_name: "Read", last_name: "Only Supporter", print_name: "Read Only Supporter",
      contact_number: "6715559002",
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    patch "/api/v1/supporters/#{supporter.id}",
      params: { supporter: { precinct_id: precinct.id } },
      headers: auth_headers(@readonly_user)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "supporter_edit_access_required", payload["code"]
  end

  test "show returns edit permissions false for non editor roles" do
    supporter = Supporter.create!(
      first_name: "Show", last_name: "Read Only", print_name: "Show Read Only",
      contact_number: "6715559003",
      village: @village,
      source: "staff_entry",
      status: "active"
    )

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@readonly_user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal false, payload.dig("permissions", "can_edit")
  end

  test "show includes referral village metadata" do
    supporter = Supporter.create!(
      first_name: "Referral", last_name: "Supporter", print_name: "Referral Supporter",
      contact_number: "6715559004",
      village: @village,
      source: "staff_entry",
      status: "active",
      verification_status: "flagged"
    )
    supporter.update_column(:referred_from_village_id, @village.id)

    get "/api/v1/supporters/#{supporter.id}", headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @village.id, payload.dig("supporter", "referred_from_village_id")
    assert_equal @village.name, payload.dig("supporter", "referred_from_village_name")
  end

  test "approve_supporter approves a pending non-duplicate submission" do
    cycle = CampaignCycle.create!(
      name: "Approval Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    current_period = QuotaPeriod.create!(
      campaign_cycle: cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 100
    )
    supporter = Supporter.create!(
      first_name: "Approve",
      last_name: "Supporter",
      print_name: "Approve Supporter",
      contact_number: "6715559998",
      village: @village,
      source: "bulk_import",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      potential_duplicate: false
    )

    patch "/api/v1/supporters/#{supporter.id}/approve_supporter", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter.reload

    assert_equal "approved", supporter.review_status
    assert_equal @data_team.id, supporter.reviewed_by_user_id
    assert_not_nil supporter.reviewed_at
    assert_equal current_period.id, supporter.quota_period_id
    assert_equal "approved", payload.dig("supporter", "review_status")
    assert_equal current_period.id, payload.dig("supporter", "quota_period_id")
  end

  test "approve_supporter uses active current cycle period when archived overlapping period exists" do
    archived_cycle = CampaignCycle.create!(
      name: "Archived Cycle",
      cycle_type: "general",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "archived"
    )
    QuotaPeriod.create!(
      campaign_cycle: archived_cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 100
    )

    active_cycle = CampaignCycle.create!(
      name: "Active Cycle",
      cycle_type: "primary",
      start_date: Date.current.beginning_of_year,
      end_date: Date.current.end_of_year,
      status: "active"
    )
    active_period = QuotaPeriod.create!(
      campaign_cycle: active_cycle,
      name: Date.current.strftime("%B %Y"),
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      due_date: Date.current.end_of_month,
      quota_target: 100
    )

    supporter = Supporter.create!(
      first_name: "Cycle",
      last_name: "Chooser",
      print_name: "Cycle Chooser",
      contact_number: "6715559988",
      village: @village,
      source: "bulk_import",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      potential_duplicate: false
    )

    patch "/api/v1/supporters/#{supporter.id}/approve_supporter", headers: auth_headers(@data_team)

    assert_response :success
    assert_equal active_period.id, supporter.reload.quota_period_id
  end

  test "approve_supporter rejects submissions with unresolved duplicate warnings" do
    supporter = Supporter.create!(
      first_name: "Duplicate",
      last_name: "Gate",
      print_name: "Duplicate Gate",
      contact_number: "6715559999",
      village: @village,
      source: "bulk_import",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      potential_duplicate: true
    )

    patch "/api/v1/supporters/#{supporter.id}/approve_supporter", headers: auth_headers(@data_team)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "duplicate_review_required", payload["code"]
    assert_equal "pending", supporter.reload.review_status
  end

  test "resolve_duplicate writes merge audit history onto kept supporter" do
    kept = Supporter.create!(
      first_name: "Audit",
      last_name: "Merge",
      print_name: "Audit Merge",
      contact_number: "6715559978",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      email: "",
      self_reported_registered_voter: false
    )
    duplicate = Supporter.create!(
      first_name: "Audit",
      last_name: "Merge",
      print_name: "Audit Merge",
      contact_number: "6715559978",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      email: "audit.merge@example.com",
      self_reported_registered_voter: true
    )

    patch "/api/v1/supporters/#{duplicate.id}/resolve_duplicate",
      params: { resolution: "merge", merge_into_id: kept.id },
      headers: auth_headers(@data_team)

    assert_response :success

    kept.reload
    assert_equal "audit.merge@example.com", kept.email
    assert_equal true, kept.self_reported_registered_voter

    kept_log = kept.audit_logs.order(created_at: :desc).find_by(action: "duplicate_merged")
    assert kept_log.present?
    assert_equal({ "from" => nil, "to" => duplicate.id }, kept_log.changed_data["merged_supporter_id"])
    assert_equal({ "from" => "", "to" => "audit.merge@example.com" }, kept_log.changed_data["email"])
    assert_equal({ "from" => false, "to" => true }, kept_log.changed_data["self_reported_registered_voter"])

    get "/api/v1/supporters/#{kept.id}", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("audit_logs").map { |log| log.fetch("action") }, "duplicate_merged"
  end

  test "rejecting one pending duplicate clears the blocker from the remaining supporter" do
    original = Supporter.create!(
      first_name: "Reject",
      last_name: "Duplicate",
      print_name: "Reject Duplicate",
      contact_number: "6715559988",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged"
    )
    duplicate = Supporter.create!(
      first_name: "Reject",
      last_name: "Duplicate",
      print_name: "Reject Duplicate",
      contact_number: "6715559989",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged"
    )

    original.reload
    duplicate.reload
    assert original.potential_duplicate?
    assert duplicate.potential_duplicate?

    patch "/api/v1/supporters/#{duplicate.id}/reject_supporter", headers: auth_headers(@data_team)

    assert_response :success
    duplicate.reload
    original.reload

    assert_equal "rejected", duplicate.review_status
    assert_equal false, duplicate.potential_duplicate
    assert_nil duplicate.duplicate_of_id
    assert_equal false, original.potential_duplicate
    assert_nil original.duplicate_of_id

    patch "/api/v1/supporters/#{original.id}/approve_supporter", headers: auth_headers(@data_team)

    assert_response :success
    assert_equal "approved", original.reload.review_status
  end

  test "vetting queue summary uses distinct review buckets" do
    Supporter.update_all(verification_status: "verified", registered_voter: true)
    other_village = Village.create!(name: "Referral Village")

    needs_review = Supporter.create!(
      first_name: "Needs", last_name: "Review", print_name: "Needs Review",
      contact_number: "6715559010",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    needs_review.update_columns(verification_status: "flagged", registered_voter: true, submitted_village_id: @village.id)
    pending_review = Supporter.create!(
      first_name: "Pending", last_name: "Review", print_name: "Pending Review",
      contact_number: "6715559011",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "unverified",
      registered_voter: true
    )
    pending_review.update_columns(verification_status: "unverified", registered_voter: true, submitted_village_id: @village.id)
    no_gec_match = Supporter.create!(
      first_name: "No", last_name: "Match", print_name: "No Match",
      contact_number: "6715559012",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "unverified",
      registered_voter: false
    )
    no_gec_match.update_columns(verification_status: "unverified", registered_voter: false, submitted_village_id: @village.id)
    referral = Supporter.create!(
      first_name: "Village", last_name: "Referral", print_name: "Village Referral",
      contact_number: "6715559013",
      village: other_village,
      submitted_village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    referral.update_columns(verification_status: "flagged", registered_voter: true, submitted_village_id: @village.id)

    get "/api/v1/supporters/vetting_queue", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 4, payload.dig("summary", "total_needing_review")
    assert_equal 1, payload.dig("summary", "flagged")
    assert_equal 1, payload.dig("summary", "unverified")
    assert_equal 1, payload.dig("summary", "unregistered")
    assert_equal 1, payload.dig("summary", "referrals")

    returned_ids = payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }
    assert_includes returned_ids, needs_review.id
    assert_includes returned_ids, pending_review.id
    assert_includes returned_ids, no_gec_match.id
    assert_includes returned_ids, referral.id

    get "/api/v1/supporters/vetting_queue",
      params: { filter: "referral" },
      headers: auth_headers(@data_team)

    assert_response :success
    referral_payload = JSON.parse(response.body)
    assert_equal [ referral.id ], referral_payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }

    get "/api/v1/supporters/vetting_queue",
      params: { filter: "flagged" },
      headers: auth_headers(@data_team)

    assert_response :success
    flagged_payload = JSON.parse(response.body)
    flagged_ids = flagged_payload.fetch("supporters").map { |supporter_payload| supporter_payload.fetch("id") }
    assert_includes flagged_ids, needs_review.id
    assert_not_includes flagged_ids, referral.id
  end

  test "vetting queue reuses precomputed verification reason payloads" do
    supporter = Supporter.create!(
      first_name: "Queue",
      last_name: "ReasonCheck",
      print_name: "Queue ReasonCheck",
      contact_number: "6715559014",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: nil,
      verification_reason_metadata: {}
    )

    village_name = @village.name
    original_find_matches = GecVoter.method(:find_matches)
    GecVoter.define_singleton_method(:find_matches) do |**|
      [ {
        gec_voter: GecVoter.new(village_name: village_name),
        confidence: :medium,
        match_type: :fuzzy_name_year,
        match_count: 1
      } ]
    end

    original_reason_new = SupporterVerificationReasonService.method(:new)
    service_calls = 0
    SupporterVerificationReasonService.define_singleton_method(:new) do |*args, **kwargs|
      service_calls += 1
      raise "duplicate reason service call" if service_calls > 1

      original_reason_new.call(*args, **kwargs)
    end

    begin
      get "/api/v1/supporters/vetting_queue",
        params: { search: "ReasonCheck" },
        headers: auth_headers(@data_team)
    ensure
      GecVoter.define_singleton_method(:find_matches, original_find_matches)
      SupporterVerificationReasonService.define_singleton_method(:new, original_reason_new)
    end

    assert_response :success
    payload = JSON.parse(response.body)
    supporter_payload = payload.fetch("supporters").find { |item| item["id"] == supporter.id }
    assert_equal "fuzzy_name_match", supporter_payload["verification_reason"]
    assert_equal 1, service_calls
  end

  test "vetting queue supports approved bucket" do
    approved = Supporter.create!(
      first_name: "Approved",
      last_name: "Queue",
      print_name: "Approved Queue",
      contact_number: "6715559201",
      village: @village,
      source: "staff_entry",
      review_status: "approved",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "verified",
      registered_voter: true
    )
    Supporter.create!(
      first_name: "Pending",
      last_name: "Queue",
      print_name: "Pending Queue",
      contact_number: "6715559202",
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )

    get "/api/v1/supporters/vetting_queue",
      params: { review_bucket: "approved", search: "Queue" },
      headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "approved", payload["current_bucket"]
    returned_ids = payload.fetch("supporters").map { |item| item["id"] }
    assert_equal [ approved.id ], returned_ids
  end

  test "revet refreshes supporter verification against current GEC data" do
    GecVoter.create!(
      first_name: "Revet",
      last_name: "Match",
      dob: Date.new(1984, 5, 10),
      village_name: @village.name,
      village_id: @village.id,
      voter_registration_number: "VR-REVET-1",
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active"
    )

    supporter = Supporter.create!(
      first_name: "Revet",
      last_name: "Match",
      print_name: "Revet Match",
      contact_number: "6715559203",
      dob: Date.new(1984, 5, 10),
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "manual_staff_flag",
      verification_reason_metadata: {}
    )

    patch "/api/v1/supporters/#{supporter.id}/revet", headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "auto_verified", payload.dig("result", "status")
    assert_equal "verified", payload.dig("supporter", "verification_status")
    assert_equal "matched_current_gec", payload.dig("supporter", "verification_reason")
  end

  test "vetting queue includes GEC precinct details for matched voters" do
    precinct = Precinct.create!(village: @village, number: "19", alpha_range: "A-Z")
    GecVoter.create!(
      first_name: "Queue",
      last_name: "Precinct",
      birth_year: 1984,
      village_name: @village.name,
      village_id: @village.id,
      precinct_id: precinct.id,
      precinct_number: "19",
      voter_registration_number: "VR-QUEUE-PCT",
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active"
    )

    supporter = Supporter.create!(
      first_name: "Queue",
      last_name: "Precinct",
      print_name: "Queue Precinct",
      contact_number: "6715559219",
      dob: Date.new(1984, 1, 1),
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "manual_staff_flag",
      verification_reason_metadata: {}
    )

    get "/api/v1/supporters/vetting_queue",
      params: { search: "Queue Precinct" },
      headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    supporter_payload = payload.fetch("supporters").find { |item| item["id"] == supporter.id }
    gec_voter = supporter_payload.fetch("gec_matches").first.fetch("gec_voter")
    assert_equal precinct.id, gec_voter["precinct_id"]
    assert_equal "19", gec_voter["precinct_number"]
  end

  test "bulk revet can apply current queue filters instead of explicit ids" do
    matching_supporter = Supporter.create!(
      first_name: "Bulk",
      last_name: "Revet",
      print_name: "Bulk Revet",
      contact_number: "6715559204",
      dob: Date.new(1986, 6, 11),
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    matching_supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "manual_staff_flag",
      verification_reason_metadata: {}
    )

    other_supporter = Supporter.create!(
      first_name: "Other",
      last_name: "Person",
      print_name: "Other Person",
      contact_number: "6715559205",
      dob: Date.new(1981, 7, 12),
      village: @village,
      source: "staff_entry",
      review_status: "pending",
      public_review_status: "not_applicable",
      status: "active",
      verification_status: "flagged",
      registered_voter: true
    )
    other_supporter.update_columns(
      verification_status: "flagged",
      registered_voter: true,
      verification_reason: "manual_staff_flag",
      verification_reason_metadata: {}
    )

    GecVoter.create!(
      first_name: "Bulk",
      last_name: "Revet",
      dob: Date.new(1986, 6, 11),
      village_name: @village.name,
      village_id: @village.id,
      voter_registration_number: "VR-BULK-1",
      gec_list_date: Date.current,
      imported_at: Time.current,
      status: "active"
    )

    post "/api/v1/supporters/bulk_revet",
      params: {
        apply_current_filters: true,
        review_bucket: "pending",
        search: "Bulk Revet"
      },
      headers: auth_headers(@data_team)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["updated"]
    assert_equal 1, payload.dig("results", "auto_verified")
    assert_equal "verified", matching_supporter.reload.verification_status
    assert_equal "flagged", other_supporter.reload.verification_status
  end
end
