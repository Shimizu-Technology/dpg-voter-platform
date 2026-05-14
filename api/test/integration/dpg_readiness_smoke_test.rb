# frozen_string_literal: true

require "test_helper"
require "tempfile"

class DpgReadinessSmokeTest < ActionDispatch::IntegrationTest
  def setup
    super
    Campaign.create!(
      name: "Democratic Party of Guam",
      election_year: 2026,
      status: "active"
    )
    @village = Village.create!(name: "Smoke Village #{SecureRandom.hex(4)}")
    @admin = User.create!(
      clerk_id: "clerk-smoke-admin-#{SecureRandom.hex(4)}",
      email: "smoke-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Smoke Admin",
      role: "campaign_admin"
    )
  end

  test "monday-ready DPG workflow works end to end" do
    previous_live_outreach = ENV["DPG_LIVE_OUTREACH_ENABLED"]
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = "true"

    get "/api/v1/campaign_info"
    assert_response :success

    get "/api/v1/villages"
    assert_response :success

    assert_difference -> { Supporter.count }, 2 do
      post "/api/v1/supporters",
        params: public_signup_payload,
        as: :json
    end
    assert_response :created
    public_payload = JSON.parse(response.body)
    assert_equal 1, public_payload["household_supporters_created"]
    assert_equal "accepted", public_payload.dig("supporter", "intake_status")
    assert_equal "pending", public_payload.dig("supporter", "review_status")
    assert_equal "not_applicable", public_payload.dig("supporter", "public_review_status")
    assert_enqueued_jobs 0

    post "/api/v1/supporters?entry_mode=staff&entry_channel=manual",
      params: {
        supporter: {
          first_name: "Staff",
          last_name: "Entry",
          contact_number: "6715550200",
          email: "staff-entry@example.com",
          street_address: "42 Committee Lane",
          village_id: @village.id,
          registered_voter: true,
          opt_in_email: true,
          opt_in_text: true
        }
      },
      headers: auth_headers(@admin),
      as: :json
    assert_response :created

    get "/api/v1/session", headers: auth_headers(@admin)
    assert_response :success

    get "/api/v1/supporters", headers: auth_headers(@admin)
    assert_response :success
    assert_operator JSON.parse(response.body)["supporters"].size, :>=, 3

    get "/api/v1/supporters",
      params: { search: "public-signup@example.com" },
      headers: auth_headers(@admin)
    assert_response :success
    public_rows = JSON.parse(response.body)["supporters"]
    assert_operator public_rows.size, :>=, 1
    assert_equal "new_intake", public_rows.first.fetch("contact_classification")
    assert_equal "pending", public_rows.first.fetch("review_status")

    get "/api/v1/supporters",
      params: { search: "public-signup@example.com", exclude_contact_classification: "new_intake" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_empty JSON.parse(response.body)["supporters"]

    get "/api/v1/supporters",
      params: { search: "public-signup@example.com", contact_classification: "new_intake" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_operator JSON.parse(response.body)["supporters"].size, :>=, 1

    get "/api/v1/supporters",
      params: { search: "Committee Lane" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_equal 1, JSON.parse(response.body)["supporters"].size

    get "/api/v1/supporters",
      params: { search: "staff-entry@example.com" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_equal 1, JSON.parse(response.body)["supporters"].size

    post "/api/v1/supporters/scan_duplicates", headers: auth_headers(@admin), as: :json
    assert_response :success

    get "/api/v1/reports", headers: auth_headers(@admin)
    assert_response :success

    get "/api/v1/reports/supporter_summary/preview",
      params: { limit: 25 },
      headers: auth_headers(@admin)
    assert_response :success

    get "/api/v1/audit_logs", headers: auth_headers(@admin)
    assert_response :success

    get "/api/v1/users", headers: auth_headers(@admin)
    assert_response :success

    assert_import_preview_parse_and_confirm

    get "/api/v1/sms/status", headers: auth_headers(@admin)
    assert_response :success
    assert_equal true, JSON.parse(response.body)["live_enabled"]

    post "/api/v1/sms/blast",
      params: { message: "DPG smoke dry run", dry_run: "true" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_equal true, JSON.parse(response.body)["dry_run"]

    get "/api/v1/email/status", headers: auth_headers(@admin)
    assert_response :success
    assert_equal true, JSON.parse(response.body)["live_enabled"]

    post "/api/v1/email/blast",
      params: { subject: "DPG smoke", body: "Hi {{first_name}}", dry_run: "true" },
      headers: auth_headers(@admin)
    assert_response :success
    assert_equal true, JSON.parse(response.body)["dry_run"]
  ensure
    ENV["DPG_LIVE_OUTREACH_ENABLED"] = previous_live_outreach
  end

  private

  def public_signup_payload
    {
      supporter: {
        first_name: "Public",
        last_name: "Signup",
        contact_number: "6715550100",
        email: "public-signup@example.com",
        street_address: "1 Smoke Test Way",
        village_id: @village.id,
        registered_voter: "yes",
        opt_in_email: false,
        opt_in_text: false,
        wants_to_volunteer: true,
        household_members: [
          {
            first_name: "Household",
            last_name: "Member",
            registered_voter: "not_sure"
          }
        ]
      }
    }
  end

  def assert_import_preview_parse_and_confirm
    csv = Tempfile.new([ "dpg-smoke-supporters", ".csv" ])
    csv.write <<~CSV
      First Name,Last Name,Phone,Email,Address,Village,Registered
      Imported,Supporter,6715550300,imported-smoke@example.com,2 Smoke Test Way,#{@village.name},yes
    CSV
    csv.rewind

    upload = Rack::Test::UploadedFile.new(csv.path, "text/csv", original_filename: "dpg-smoke-supporters.csv")
    post "/api/v1/imports/preview",
      params: { file: upload },
      headers: auth_headers(@admin)
    assert_response :success

    preview_payload = JSON.parse(response.body)
    import_key = preview_payload.fetch("import_key")
    sheet = preview_payload.fetch("sheets").first
    assert_equal 1, sheet.fetch("row_count")

    post "/api/v1/imports/parse",
      params: {
        import_key: import_key,
        sheet_index: sheet.fetch("index"),
        column_mapping: {
          header_row: 1,
          columns: {
            first_name: 1,
            last_name: 2,
            contact_number: 3,
            email: 4,
            street_address: 5,
            village: 6,
            registered_voter: 7
          }
        }
      },
      headers: auth_headers(@admin),
      as: :json
    assert_response :success

    parse_payload = JSON.parse(response.body)
    assert_equal 1, parse_payload.fetch("valid_count")

    assert_difference -> { Supporter.where(source: "bulk_import").count }, 1 do
      post "/api/v1/imports/confirm",
        params: {
          import_key: import_key,
          rows: parse_payload.fetch("rows")
        },
        headers: auth_headers(@admin),
        as: :json
    end
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("created")

    get "/api/v1/supporters",
      params: { search: "imported-smoke@example.com" },
      headers: auth_headers(@admin)
    assert_response :success
    imported_supporters = JSON.parse(response.body).fetch("supporters")
    assert_equal 1, imported_supporters.size
    assert_equal "approved", imported_supporters.first.fetch("review_status")
  ensure
    csv&.close!
  end
end
