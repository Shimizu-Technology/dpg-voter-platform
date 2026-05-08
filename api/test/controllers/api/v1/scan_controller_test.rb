# frozen_string_literal: true

require "test_helper"

class Api::V1::ScanControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.create!(name: "Scan Test Village")
    @user = User.create!(
      clerk_id: "clerk-scan-user",
      email: "scan-user@example.com",
      name: "Scan User",
      role: "block_leader",
      assigned_village_id: @village.id
    )
  end

  test "batch returns extracted rows" do
    original_method = FormScanner.method(:extract_batch)
    FormScanner.singleton_class.send(:define_method, :extract_batch) do |_image_data, default_village_id: nil|
      {
        success: true,
        rows: [
          {
            "_row" => 1,
            "_skip" => false,
            "_issues" => [],
            "first_name" => "Ana",
            "last_name" => "Cruz",
            "contact_number" => "671-555-1212",
            "village_id" => default_village_id || @village.id
          }
        ]
      }
    end

    begin
      post "/api/v1/scan/batch",
        params: {
          image: "data:image/jpeg;base64,abc123",
          default_village_id: @village.id
        },
        headers: auth_headers(@user)
    ensure
      FormScanner.singleton_class.send(:define_method, :extract_batch, original_method)
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["success"]
    assert_equal 1, payload["total_detected"]
    assert_equal "Ana", payload.dig("rows", 0, "first_name")
  end

  test "batch rejects invalid default village" do
    post "/api/v1/scan/batch",
      params: {
        image: "data:image/jpeg;base64,abc123",
        default_village_id: 999_999
      },
      headers: auth_headers(@user)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "invalid_default_village", payload["code"]
  end

  test "batch requires image data" do
    post "/api/v1/scan/batch",
      params: { default_village_id: @village.id },
      headers: auth_headers(@user)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "image_data_required", payload["code"]
  end

  test "telemetry accepts post-save metrics" do
    post "/api/v1/scan/telemetry",
      params: {
        telemetry: {
          total_detected: 28,
          included_before_save: 23,
          created: 21,
          failed: 2,
          skipped: 5,
          rows_with_any_issues: 9,
          rows_with_critical_issues: 3,
          rows_with_warning_only: 6,
          scan_warning_present: false,
          save_duration_ms: 4123,
          default_village_id: @village.id,
          issue_counts: {
            phone_missing: 7,
            stateside_address: 2
          }
        }
      },
      headers: auth_headers(@user)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["success"]
  end
end
