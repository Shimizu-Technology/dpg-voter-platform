require "test_helper"

class Api::V1::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.create!(name: "Import Audit Village")
    @other_village = Village.create!(name: "Import Other Village")
    @user = User.create!(
      clerk_id: "clerk-import-audit-user",
      email: "import-audit@example.com",
      name: "Import Auditor",
      role: "campaign_admin"
    )
    @chief = User.create!(
      clerk_id: "clerk-import-chief-user",
      email: "import-chief@example.com",
      name: "Import Chief",
      role: "village_chief",
      assigned_village_id: @village.id
    )
    @poll_watcher = User.create!(
      clerk_id: "clerk-import-poll-watcher",
      email: "import-poll-watcher@example.com",
      name: "Import Poll Watcher",
      role: "poll_watcher"
    )
  end

  test "confirm writes per-supporter created audit logs" do
    first_one = "AnaImport#{SecureRandom.hex(2)}"
    first_two = "BenImport#{SecureRandom.hex(2)}"

    post "/api/v1/imports/confirm",
      params: {
        import_key: "a" * 32,
        village_id: @village.id,
        rows: [
          {
            "_row" => 1,
            "first_name" => first_one,
            "last_name" => "Cruz",
            "contact_number" => nil,
            "registered_voter" => true
          },
          {
            "_row" => 2,
            "first_name" => first_two,
            "last_name" => "Santos",
            "contact_number" => "671-555-1212",
            "registered_voter" => true
          }
        ]
      },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 2, payload["created"]

    supporters = Supporter.where(first_name: [ first_one, first_two ]).order(:first_name)
    assert_equal 2, supporters.count

    supporters.each do |supporter|
      created_log = AuditLog.where(auditable: supporter, action: "created").order(created_at: :desc).first
      assert_not_nil created_log
      assert_equal @user.id, created_log.actor_user_id
      assert_equal "bulk_import", created_log.metadata["entry_mode"]
      assert_equal supporter.id, created_log.auditable_id
      assert_equal "Supporter", created_log.auditable_type
      assert_equal supporter.first_name, created_log.changed_data.dig("first_name", "to")
    end
  end

  test "confirm routes imported supporters into pending supporter review" do
    imported_name = "PendingImport#{SecureRandom.hex(2)}"

    post "/api/v1/imports/confirm",
      params: {
        import_key: "b" * 32,
        village_id: @village.id,
        rows: [
          {
            "_row" => 1,
            "first_name" => imported_name,
            "last_name" => "Cruz",
            "contact_number" => nil,
            "registered_voter" => true
          }
        ]
      },
      headers: auth_headers(@user)

    assert_response :success

    supporter = Supporter.find_by!(first_name: imported_name, last_name: "Cruz")
    assert_equal "bulk_import", supporter.source
    assert_equal "bulk_import", supporter.attribution_method
    assert_equal "accepted", supporter.intake_status
    assert_equal "pending", supporter.review_status
    assert_equal "not_applicable", supporter.public_review_status
    assert_includes Supporter.pending_supporter_review, supporter
    refute_includes Supporter.official_supporters, supporter
  end

  test "village chief can import supporters within assigned village scope" do
    imported_name = "ScopedImport#{SecureRandom.hex(2)}"

    post "/api/v1/imports/confirm",
      params: {
        import_key: "c" * 32,
        village_id: @village.id,
        rows: [
          {
            "_row" => 1,
            "first_name" => imported_name,
            "last_name" => "Chief",
            "contact_number" => nil,
            "registered_voter" => true
          }
        ]
      },
      headers: auth_headers(@chief)

    assert_response :success
    supporter = Supporter.find_by!(first_name: imported_name, last_name: "Chief")
    assert_equal @village.id, supporter.village_id
  end

  test "village chief cannot import supporters outside assigned village scope" do
    post "/api/v1/imports/confirm",
      params: {
        import_key: "d" * 32,
        village_id: @other_village.id,
        rows: [
          {
            "_row" => 1,
            "first_name" => "OutOfScope",
            "last_name" => "Chief",
            "contact_number" => nil,
            "registered_voter" => true
          }
        ]
      },
      headers: auth_headers(@chief)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "village_scope_denied", payload["code"]
  end

  test "poll watcher cannot access supporter imports" do
    post "/api/v1/imports/confirm",
      params: {
        import_key: "e" * 32,
        village_id: @village.id,
        rows: []
      },
      headers: auth_headers(@poll_watcher)

    assert_response :forbidden
    payload = JSON.parse(response.body)
    assert_equal "supporter_import_access_required", payload["code"]
  end
end
