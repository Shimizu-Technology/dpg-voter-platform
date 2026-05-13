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

  test "index filters by village precinct and link status" do
    other_village = Village.find_or_create_by!(name: "Dededo")
    GecVoter.create!(
      first_name: "Other",
      last_name: "Voter",
      village: other_village,
      village_name: other_village.name,
      precinct_number: "22",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
    contact = Supporter.create!(
      first_name: "Juan",
      last_name: "Contact",
      contact_number: "671-555-0102",
      village: @village,
      source: "staff_entry",
      attribution_method: "staff_manual",
      contact_classification: "supporter",
      status: "active"
    )
    contact.update!(gec_voter: @voter)

    get "/api/v1/gec_voters",
      params: { village: @village.name, precinct_number: @voter.precinct_number, linked_status: "linked", sort: "name", direction: "desc" },
      headers: auth_headers(@leader)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ @voter.id ], payload["gec_voters"].map { |row| row["id"] }
    assert_equal 1, payload["gec_voters"].first["linked_contact_count"]
    assert_equal contact.id, payload["gec_voters"].first.dig("linked_contact", "id")
    assert_equal "supporter", payload["gec_voters"].first.dig("linked_contact", "contact_classification")
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

  test "imports endpoint merges live background progress cache" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec-voters.csv",
      status: "processing",
      import_type: "full_list",
      metadata: { "stage" => "queued", "progress_percent" => 0 }
    )
    progress = { "stage" => "importing", "progress_percent" => 67, "pages_processed" => 500, "page_count" => 760 }
    cache = Rails.cache
    original_read = cache.method(:read)
    cache.define_singleton_method(:read) do |key, *args, **kwargs|
      key == "gec_import_progress:#{import.id}" ? progress : original_read.call(key, *args, **kwargs)
    end

    get "/api/v1/gec_voters/imports", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    row = payload["imports"].find { |entry| entry["id"] == import.id }
    assert_equal "importing", row.dig("metadata", "stage")
    assert_equal 67, row.dig("metadata", "progress_percent")
    assert_equal 500, row.dig("metadata", "pages_processed")
  ensure
    Rails.cache.define_singleton_method(:read, original_read) if original_read
  end

  test "admin can enqueue a PDF preview job" do
    pdf = Tempfile.new([ "gec-preview", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-february.pdf")

    original_s3_enabled = S3Service.method(:enabled?)
    S3Service.define_singleton_method(:enabled?) { false }
    assert_enqueued_with(job: GecPdfPreviewJob) do
      post "/api/v1/gec_voters/preview",
        params: { file: upload, preview_request_id: "preview-pdf-test" },
        headers: auth_headers(@admin)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["async"]
    assert_equal "pdf", payload["source_type"]
    assert_equal "pending", payload["status"]
    assert_equal "preview-pdf-test", payload["preview_request_id"]
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    pdf&.close!
  end

  test "PDF preview storage failures return JSON errors" do
    pdf = Tempfile.new([ "gec-preview-s3-fail", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-preview-fail.pdf")

    original_s3_enabled = S3Service.method(:enabled?)
    original_s3_upload = S3Service.method(:upload)
    S3Service.define_singleton_method(:enabled?) { true }
    S3Service.define_singleton_method(:upload) { |_key, _io, content_type: nil| false }

    assert_no_difference -> { GecPdfPreview.count } do
      post "/api/v1/gec_voters/preview",
        params: { file: upload, preview_request_id: "preview-storage-fail-test" },
        headers: auth_headers(@admin)
    end

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "pdf_preview_storage_failed", payload["code"]
    assert_match "Could not store PDF preview upload", payload["error"]
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    S3Service.define_singleton_method(:upload, original_s3_upload) if original_s3_upload
    pdf&.close!
  end

  test "admin can read completed PDF preview status" do
    preview = GecPdfPreview.create!(
      preview_request_id: "completed-preview-test",
      uploaded_by_user: @admin,
      filename: "gec-february.pdf",
      content_type: "application/pdf",
      status: "completed",
      file_data: "%PDF-1.4",
      result_data: {
        "qa" => { "status" => "pass" },
        "warnings" => [],
        "row_count" => 1,
        "preview_rows" => [
          { "first_name" => "Juan", "last_name" => "Cruz", "village_name" => "Barrigada" }
        ]
      }
    )

    get "/api/v1/gec_voters/preview_status",
      params: { preview_request_id: preview.preview_request_id },
      headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["async"]
    assert_equal "completed", payload["status"]
    assert_equal 1, payload["row_count"]
    assert_equal "Juan", payload["preview_rows"].first["first_name"]
  end

  test "preview status returns not found for unknown preview request" do
    get "/api/v1/gec_voters/preview_status",
      params: { preview_request_id: "missing-preview-test" },
      headers: auth_headers(@admin)

    assert_response :not_found
    assert_equal "preview_not_found", JSON.parse(response.body)["code"]
  end

  test "preview status requires GEC import access" do
    get "/api/v1/gec_voters/preview_status",
      params: { preview_request_id: "leader-preview-test" },
      headers: auth_headers(@leader)

    assert_response :forbidden
    assert_equal "gec_import_access_required", JSON.parse(response.body)["code"]
  end

  test "PDF upload requires review confirmation before background import" do
    pdf = Tempfile.new([ "gec-upload", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-february.pdf")

    post "/api/v1/gec_voters/upload",
      params: { file: upload, gec_list_date: "2026-02-25", import_type: "full_list" },
      headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    assert_equal "pdf_review_confirmation_required", JSON.parse(response.body)["code"]
  ensure
    pdf&.close!
  end

  test "PDF upload rejects files over the import size limit before storing payload" do
    pdf = Tempfile.new([ "gec-upload-large", ".pdf" ])
    pdf.binmode
    pdf.truncate(Api::V1::GecVotersController::MAX_GEC_UPLOAD_BYTES + 1)
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-large.pdf")

    assert_no_difference -> { GecImport.count } do
      assert_no_difference -> { GecImportUpload.count } do
        post "/api/v1/gec_voters/upload",
          params: {
            file: upload,
            gec_list_date: "2026-02-25",
            import_type: "full_list",
            confirm_review: "true"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :unprocessable_entity
    assert_equal "file_too_large", JSON.parse(response.body)["code"]
  ensure
    pdf&.close!
  end

  test "admin can enqueue a confirmed PDF import job" do
    pdf = Tempfile.new([ "gec-upload-confirmed", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-february.pdf")
    original_s3_enabled = S3Service.method(:enabled?)
    S3Service.define_singleton_method(:enabled?) { false }

    assert_difference -> { GecImport.count }, 1 do
      assert_difference -> { GecImportUpload.count }, 1 do
        assert_enqueued_with(job: GecImportJob) do
          post "/api/v1/gec_voters/upload",
            params: {
              file: upload,
              gec_list_date: "2026-02-25",
              import_type: "full_list",
              confirm_review: "true"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal true, payload["async"]
    assert_equal "pending", payload.dig("import", "status")
    assert_equal "pdf", payload.dig("import", "metadata", "source_type")
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    pdf&.close!
  end

  test "confirmed PDF import stores upload payload in S3 when configured" do
    pdf = Tempfile.new([ "gec-upload-s3", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-s3.pdf")
    uploaded_keys = []

    original_s3_enabled = S3Service.method(:enabled?)
    original_s3_upload = S3Service.method(:upload)
    S3Service.define_singleton_method(:enabled?) { true }
    S3Service.define_singleton_method(:upload) do |key, io, content_type: nil|
      uploaded_keys << [ key, io.read, content_type ]
      true
    end

    assert_difference -> { GecImportUpload.count }, 1 do
      assert_enqueued_with(job: GecImportJob) do
        post "/api/v1/gec_voters/upload",
          params: {
            file: upload,
            gec_list_date: "2026-02-25",
            import_type: "full_list",
            confirm_review: "true"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :accepted
    payload = GecImportUpload.order(:id).last
    assert_nil payload.file_data
    assert_match %r{\Agec-imports/\d+/raw/gec-s3\.pdf\z}, payload.file_s3_key
    assert_equal payload.file_s3_key, uploaded_keys.first.first
    assert_equal "application/pdf", uploaded_keys.first.third
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    S3Service.define_singleton_method(:upload, original_s3_upload) if original_s3_upload
    pdf&.close!
  end

  test "failed PDF upload storage marks import failed instead of leaving it pending" do
    pdf = Tempfile.new([ "gec-upload-s3-fail", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-s3-fail.pdf")

    original_s3_enabled = S3Service.method(:enabled?)
    original_s3_upload = S3Service.method(:upload)
    S3Service.define_singleton_method(:enabled?) { true }
    S3Service.define_singleton_method(:upload) { |_key, _io, content_type: nil| false }

    assert_difference -> { GecImport.count }, 1 do
      assert_no_difference -> { GecImportUpload.count } do
        post "/api/v1/gec_voters/upload",
          params: {
            file: upload,
            gec_list_date: "2026-02-25",
            import_type: "full_list",
            confirm_review: "true"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :unprocessable_entity
    assert_equal "pdf_import_storage_failed", JSON.parse(response.body)["code"]
    failed_import = GecImport.order(:id).last
    assert_equal "failed", failed_import.status
    assert_equal "failed", failed_import.metadata["stage"]
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    S3Service.define_singleton_method(:upload, original_s3_upload) if original_s3_upload
    pdf&.close!
  end

  test "confirmed PDF import preserves changes only import type" do
    pdf = Tempfile.new([ "gec-upload-changes-only", ".pdf" ])
    pdf.binmode
    pdf.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    pdf.rewind
    upload = Rack::Test::UploadedFile.new(pdf.path, "application/pdf", original_filename: "gec-changes.pdf")
    original_s3_enabled = S3Service.method(:enabled?)
    S3Service.define_singleton_method(:enabled?) { false }

    assert_enqueued_with(job: GecImportJob) do
      post "/api/v1/gec_voters/upload",
        params: {
          file: upload,
          gec_list_date: "2026-02-25",
          import_type: "changes_only",
          confirm_review: "true"
        },
        headers: auth_headers(@admin)
    end

    assert_response :accepted
    payload = JSON.parse(response.body)
    assert_equal "changes_only", payload.dig("import", "import_type")
    assert_equal "changes_only", GecImport.order(:created_at).last.import_type
  ensure
    S3Service.define_singleton_method(:enabled?, original_s3_enabled) if original_s3_enabled
    pdf&.close!
  end

  test "admin can inspect import changes and skipped rows" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec-voters.csv",
      status: "completed",
      import_type: "full_list"
    )
    GecImportChange.create!(
      gec_import: import,
      change_type: "new",
      row_number: 2,
      first_name: "New",
      last_name: "Voter",
      village_name: @village.name,
      voter_registration_number: "NEW-123"
    )
    skipped_row = GecImportSkippedRow.create!(
      gec_import: import,
      row_number: 3,
      message: "Missing birth year",
      source_name: "Skipped Voter",
      first_name: "Skipped",
      last_name: "Voter",
      village_name: @village.name
    )

    get "/api/v1/gec_voters/imports/#{import.id}/changes",
      params: { type: "new" },
      headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["changes"].length
    assert_equal "NEW-123", payload["changes"].first["voter_registration_number"]

    get "/api/v1/gec_voters/imports/#{import.id}/skipped_rows",
      params: { status: "pending" },
      headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal skipped_row.id, payload["skipped_rows"].first["id"]

    post "/api/v1/gec_voters/imports/#{import.id}/skipped_rows/#{skipped_row.id}/dismiss",
      headers: auth_headers(@admin)

    assert_response :success
    assert_equal "dismissed", skipped_row.reload.resolution_status
  end

  test "skipped row resolution preview uses nested corrected values" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec-voters.csv",
      status: "completed",
      import_type: "full_list"
    )
    skipped_row = GecImportSkippedRow.create!(
      gec_import: import,
      row_number: 4,
      message: "Missing parsed name",
      village_name: @village.name,
      birth_year: 1979
    )

    post "/api/v1/gec_voters/imports/#{import.id}/skipped_rows/#{skipped_row.id}/preview_resolution",
      params: {
        corrected_values: {
          first_name: "Maria",
          last_name: "Santos",
          village_name: @village.name,
          birth_year: "1979"
        }
      },
      headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "ready_to_create", payload.dig("preview", "status")
    assert_equal "Maria", payload.dig("preview", "corrected_values", "first_name")
    assert_equal "Santos", payload.dig("preview", "corrected_values", "last_name")
  end

  test "import data endpoint reports unavailable parsed artifact cleanly" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec-voters.csv",
      status: "completed",
      import_type: "full_list"
    )

    get "/api/v1/gec_voters/imports/#{import.id}/view_data", headers: auth_headers(@admin)

    assert_response :not_found
    assert_equal "parsed_data_not_available", JSON.parse(response.body)["code"]
  end

  test "import data endpoint falls back to recorded change rows when artifact is missing" do
    import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec-voters.csv",
      status: "completed",
      import_type: "full_list"
    )
    GecImportChange.create!(
      gec_import: import,
      change_type: "new",
      row_number: 1,
      first_name: "Fallback",
      last_name: "Voter",
      village_name: @village.name,
      voter_registration_number: "FALL-123",
      birth_year: 1988,
      details: { "address" => "12 Test Street", "precinct_number" => "15A" }
    )

    get "/api/v1/gec_voters/imports/#{import.id}/view_data", headers: auth_headers(@admin)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "change_fallback", payload.dig("preview", "source_type")
    assert_equal 1, payload.dig("preview", "pagination", "total_rows")
    row = payload.dig("preview", "preview_rows").first
    assert_equal "Fallback", row["first_name"]
    assert_equal "12 Test Street", row["address"]
    assert_includes payload.dig("preview", "warnings").first, "reconstructed"
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
