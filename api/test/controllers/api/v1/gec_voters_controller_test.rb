require "test_helper"
require "tempfile"

class Api::V1::GecVotersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    @admin = User.create!(
      clerk_id: "clerk-gec-test-admin-#{SecureRandom.hex(4)}",
      email: "gec-admin-#{SecureRandom.hex(4)}@example.com",
      name: "GEC Admin",
      role: "campaign_admin"
    )
    @coordinator = User.create!(
      clerk_id: "clerk-gec-test-coordinator-#{SecureRandom.hex(4)}",
      email: "gec-coordinator-#{SecureRandom.hex(4)}@example.com",
      name: "GEC Coordinator",
      role: "district_coordinator"
    )

    # Create some GEC voters for testing
    @gec_voter = GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      village_name: "Barrigada",
      voter_registration_number: "VR12345",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )

    GecVoter.create!(
      first_name: "Maria",
      last_name: "Santos",
      dob: Date.new(1990, 6, 20),
      village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )

    GecVoter.create!(
      first_name: "Pedro",
      last_name: "Reyes",
      dob: Date.new(1975, 11, 8),
      village_name: "Dededo",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )
  end

  test "index returns paginated GEC voters" do
    get "/api/v1/gec_voters", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["gec_voters"].is_a?(Array)
    assert json["pagination"]["total"] >= 3
  end

  test "district coordinator cannot access gec voter data ops endpoints" do
    get "/api/v1/gec_voters", headers: auth_headers(@coordinator)

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal "data_ops_access_required", json["code"]
  end

  test "activates a completed import as the election-day GEC list" do
    old_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "old.csv",
      status: "completed",
      import_type: "full_list",
      active_election_day: true,
      activated_for_election_at: Time.zone.parse("2026-04-01 08:30:00"),
      activated_for_election_by_user: @admin
    )
    new_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "new.csv",
      status: "completed",
      import_type: "full_list"
    )

    post "/api/v1/gec_voters/imports/#{new_import.id}/activate_election_day", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal new_import.id, json.dig("import", "id")
    assert_equal true, json.dig("import", "active_election_day")
    assert_equal false, old_import.reload.active_election_day
    assert_equal Time.zone.parse("2026-04-01 08:30:00"), old_import.activated_for_election_at
    assert_equal @admin.id, old_import.activated_for_election_by_user_id
    assert_equal true, new_import.reload.active_election_day
    assert_equal @admin.id, new_import.activated_for_election_by_user_id
  end

  test "does not activate an incomplete import as election-day list" do
    pending_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "pending.csv",
      status: "pending",
      import_type: "full_list"
    )

    post "/api/v1/gec_voters/imports/#{pending_import.id}/activate_election_day", headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "import_not_completed", json["code"]
  end

  test "index filters by village" do
    get "/api/v1/gec_voters", params: { village: "Barrigada" }, headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    json["gec_voters"].each do |voter|
      assert_equal "Barrigada", voter["village_name"]
    end
  end

  test "index filters by village_id" do
    get "/api/v1/gec_voters", params: { village_id: @village.id, q: "Juan" }, headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["gec_voters"].all? { |voter| voter["village_id"] == @village.id }
    assert json["gec_voters"].any? { |voter| voter["first_name"] == "Juan" }
  end

  test "index filters by last name prefix" do
    get "/api/v1/gec_voters", params: { last_name: "Cru" }, headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["gec_voters"].any? { |v| v["last_name"] == "Cruz" }
  end

  test "index returns address data when available" do
    precinct = Precinct.create!(village: @village, number: "19", alpha_range: "A-Z")
    @gec_voter.update!(address: "123 TEST ST", precinct: precinct, precinct_number: "19")

    get "/api/v1/gec_voters", params: { q: "Juan Cruz" }, headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    voter = json["gec_voters"].find { |entry| entry["id"] == @gec_voter.id }
    assert_equal "123 TEST ST", voter["address"]
    assert_equal precinct.id, voter["precinct_id"]
    assert_equal "19", voter["precinct_number"]
  end

  test "index q search matches split names without requiring exact middle-name text" do
    GecVoter.create!(
      first_name: "James",
      middle_name: "G.",
      last_name: "Shimizu",
      dob: Date.new(1980, 1, 1),
      village_name: "Hagatna",
      voter_registration_number: "VR-SHIMIZU-1",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: Time.current
    )

    get "/api/v1/gec_voters", params: { q: "James Shimizu" }, headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["gec_voters"].any? { |voter| voter["first_name"] == "James" && voter["last_name"] == "Shimizu" }
  end

  test "stats returns overview" do
    get "/api/v1/gec_voters/stats", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["total_voters"] >= 3
    assert json["villages"].is_a?(Array)
    assert json.key?("official_village_count")
    assert json.key?("unassigned_gec_voters")
  end

  test "stats canonicalize legacy village aliases into shared village buckets" do
    humatak = Village.find_or_create_by!(name: "Humåtak")
    malesso = Village.find_or_create_by!(name: "Malesso'")
    unassigned = Village.find_or_create_by!(name: "Unassigned")

    humatak_voter = GecVoter.create!(
      first_name: "Legacy",
      last_name: "Humatak",
      village_name: "Humåtak",
      village: humatak,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
    humatak_voter.update_columns(village_name: "HUMATAK", village_id: nil)

    malesso_voter = GecVoter.create!(
      first_name: "Legacy",
      last_name: "Malesso",
      village_name: "Malesso'",
      village: malesso,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )
    malesso_voter.update_columns(village_name: "MALESSO", village_id: nil)

    GecVoter.create!(
      first_name: "Legacy",
      last_name: "Unassigned",
      village_name: "Unassigned",
      village: unassigned,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )

    get "/api/v1/gec_voters/stats", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    villages = json["villages"].index_by { |row| row["name"] }

    assert_equal 1, villages["Humåtak"]["count"]
    assert_equal 1, villages["Malesso'"]["count"]
    assert_nil villages["HUMATAK"]
    assert_nil villages["MALESSO"]
    assert villages.key?("Unassigned")
    assert_equal 1, json["unassigned_gec_voters"]
    assert_equal villages.length - 1, json["official_village_count"]
  end

  test "stats routes unknown active village strings into unassigned bucket" do
    unassigned = Village.find_or_create_by!(name: "Unassigned")

    GecVoter.create!(
      first_name: "Foreign",
      last_name: "Address",
      village_name: "FPO",
      village: nil,
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: Time.current
    )

    get "/api/v1/gec_voters/stats", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    villages = json["villages"].index_by { |row| row["name"] }

    assert villages.key?(unassigned.name)
    assert_not villages.key?("FPO")
  end

  test "match finds exact match by name + dob + village" do
    post "/api/v1/gec_voters/match",
      params: { first_name: "Juan", last_name: "Cruz", dob: "1985-03-15", village_name: "Barrigada" },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["matches"].any? { |m| m["confidence"] == "exact" }
  end

  test "match detects different village (potential referral)" do
    post "/api/v1/gec_voters/match",
      params: { first_name: "Juan", last_name: "Cruz", dob: "1985-03-15", village_name: "Dededo" },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["matches"].any? { |m| m["match_type"] == "different_village" }
  end

  test "match returns empty for unknown person" do
    post "/api/v1/gec_voters/match",
      params: { first_name: "Nonexistent", last_name: "Person", dob: "2000-01-01", village_name: "Barrigada" },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["matches"].size
  end

  test "upload requires admin" do
    non_admin = User.create!(
      clerk_id: "clerk-gec-nonadmin-#{SecureRandom.hex(4)}",
      email: "gec-nonadmin-#{SecureRandom.hex(4)}@example.com",
      name: "Regular User",
      role: "block_leader"
    )

    post "/api/v1/gec_voters/upload",
      params: { file: fixture_file_upload("test/fixtures/files/empty.txt", "text/plain"), gec_list_date: "2026-02-25" },
      headers: auth_headers(non_admin)

    assert_response :forbidden
  end

  test "imports lists past imports" do
    GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 50000
    )

    get "/api/v1/gec_voters/imports", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["imports"].any?
  end

  test "imports includes uploaded_by_email" do
    GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 50000,
      uploaded_by_user: @admin
    )

    get "/api/v1/gec_voters/imports", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    imp = json["imports"].first
    assert_equal @admin.email, imp["uploaded_by_email"]
  end

  test "imports includes transparency flags" do
    GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 50000,
      raw_file_s3_key: "gec-imports/1/raw/gec_jan_2026.xlsx",
      raw_filename: "gec_jan_2026.xlsx",
      original_file_s3_key: "gec-imports/1/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    get "/api/v1/gec_voters/imports", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    imp = json["imports"].first
    assert_equal true, imp["has_import_artifact"]
    assert_equal true, imp["has_original_file"]
    assert_equal true, imp["has_downloadable_file"]
  end

  test "pdf preview queues in background and returns completed preview via status endpoint" do
    file = Tempfile.new([ "gec_preview", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    fake_result = GecPdfParserService::Result.new(
      rows: [
        {
          "name" => "JUAN CRUZ",
          "village" => "Barrigada",
          "voter_registration_number" => "96001",
          "birth_year" => "1985"
        }
      ],
      qa: {
        status: "preview",
        row_count: 1,
        quality_score: nil,
        preview_mode: true,
        note: "Sample preview only. Full PDF validation runs during import.",
        pages_sampled: 1,
        page_count: 20
      },
      warnings: [],
      errors: []
    )

    fake_parser = Object.new
    fake_parser.define_singleton_method(:parse_preview_sample) { fake_result }

    with_singleton_stubs(GecPdfParserService, new: fake_parser) do
      assert_enqueued_jobs 1, only: GecPdfPreviewJob do
        post "/api/v1/gec_voters/preview",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
            preview_request_id: "preview-req-1"
          },
          headers: auth_headers(@admin)
      end

      preview = GecPdfPreview.find_by!(preview_request_id: "preview-req-1")
      GecPdfPreviewJob.perform_now(gec_pdf_preview_id: preview.id)
    end

    assert_response :accepted
    queued_json = JSON.parse(response.body)
    assert_equal true, queued_json["async"]
    assert_equal "pdf", queued_json["source_type"]
    assert_equal "preview-req-1", queued_json["preview_request_id"]
    assert_equal "pending", queued_json["status"]

    get "/api/v1/gec_voters/preview_status",
      params: { preview_request_id: "preview-req-1" },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "pdf", json["source_type"]
    assert_equal "completed", json["status"]
    assert_equal "preview", json["qa"]["status"]
    assert_equal true, json["qa"]["preview_mode"]
    assert_nil json["parse_cache_key"]
    assert_equal "JUAN CRUZ", json["preview_rows"][0]["name"]
  ensure
    file&.close!
  end

  test "pdf preview reuses existing preview when concurrent create hits unique constraint" do
    file = Tempfile.new([ "gec_preview_race", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-race-1",
      uploaded_by_user: @admin,
      filename: "gec_list.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4 sample"
    )

    singleton = class << GecPdfPreview; self; end
    original_find_by = singleton.instance_method(:find_by)
    original_create = singleton.instance_method(:create!)
    find_by_calls = 0

    singleton.define_method(:find_by) do |*args, **kwargs|
      find_by_calls += 1
      return nil if find_by_calls == 1

      original_find_by.bind_call(self, *args, **kwargs)
    end
    singleton.define_method(:create!) do |*args, **kwargs|
      raise ActiveRecord::RecordNotUnique, "duplicate preview request"
    end

    assert_no_enqueued_jobs only: GecPdfPreviewJob do
      post "/api/v1/gec_voters/preview",
        params: {
          file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
          preview_request_id: "preview-race-1"
        },
        headers: auth_headers(@admin)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "preview-race-1", json["preview_request_id"]
    assert_equal "pending", json["status"]
    assert_equal preview.id, GecPdfPreview.find_by!(preview_request_id: "preview-race-1").id
  ensure
    singleton.send(:remove_method, :find_by) if singleton.method_defined?(:find_by)
    singleton.send(:remove_method, :create!) if singleton.method_defined?(:create!)
    singleton.define_method(:find_by, original_find_by) if original_find_by
    singleton.define_method(:create!, original_create) if original_create
    file&.close!
  end

  test "pdf preview reuses existing preview when concurrent create hits uniqueness validation" do
    file = Tempfile.new([ "gec_preview_validation_race", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    preview = GecPdfPreview.create!(
      preview_request_id: "preview-race-2",
      uploaded_by_user: @admin,
      filename: "gec_list.pdf",
      content_type: "application/pdf",
      status: "pending",
      file_data: "%PDF-1.4 sample"
    )

    singleton = class << GecPdfPreview; self; end
    original_find_by = singleton.instance_method(:find_by)
    original_create = singleton.instance_method(:create!)
    find_by_calls = 0

    singleton.define_method(:find_by) do |*args, **kwargs|
      find_by_calls += 1
      return nil if find_by_calls == 1

      original_find_by.bind_call(self, *args, **kwargs)
    end
    singleton.define_method(:create!) do |*args, **kwargs|
      duplicate = new(*args, **kwargs)
      duplicate.errors.add(:preview_request_id, :taken)
      raise ActiveRecord::RecordInvalid.new(duplicate)
    end

    assert_no_enqueued_jobs only: GecPdfPreviewJob do
      post "/api/v1/gec_voters/preview",
        params: {
          file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
          preview_request_id: "preview-race-2"
        },
        headers: auth_headers(@admin)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "preview-race-2", json["preview_request_id"]
    assert_equal "pending", json["status"]
    assert_equal preview.id, GecPdfPreview.find_by!(preview_request_id: "preview-race-2").id
  ensure
    singleton.send(:remove_method, :find_by) if singleton.method_defined?(:find_by)
    singleton.send(:remove_method, :create!) if singleton.method_defined?(:create!)
    singleton.define_method(:find_by, original_find_by) if original_find_by
    singleton.define_method(:create!, original_create) if original_create
    file&.close!
  end

  test "pdf preview stores source in s3 when available" do
    file = Tempfile.new([ "gec_preview_s3", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    uploaded = []
    upload = lambda do |key, data, content_type:|
      uploaded << { key: key, body: data.read, content_type: content_type }
      key
    end

    with_singleton_stubs(S3Service, enabled?: true, upload: upload) do
      assert_enqueued_jobs 1, only: GecPdfPreviewJob do
        post "/api/v1/gec_voters/preview",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
            preview_request_id: "preview-s3-1"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :accepted
    preview = GecPdfPreview.find_by!(preview_request_id: "preview-s3-1")
    assert_nil preview.file_data
    assert_equal "gec-pdf-previews/preview-s3-1/source/gec_list.pdf", preview.file_s3_key
    assert_equal "%PDF-1.4 sample", uploaded.first[:body]
    assert_equal "application/pdf", uploaded.first[:content_type]
  ensure
    file&.close!
  end

  test "pdf preview marks preview failed when enqueueing background job fails" do
    file = Tempfile.new([ "gec_preview_enqueue_failure", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(GecPdfPreviewJob, perform_later: ->(*_args, **_kwargs) { raise StandardError, "queue unavailable" }) do
      assert_no_enqueued_jobs only: GecPdfPreviewJob do
        post "/api/v1/gec_voters/preview",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
            preview_request_id: "preview-enqueue-failure-1"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "preview-enqueue-failure-1", json["preview_request_id"]
    assert_equal "failed", json["status"]
    assert_match(/Failed to queue PDF preview: queue unavailable/, json["error"])

    preview = GecPdfPreview.find_by!(preview_request_id: "preview-enqueue-failure-1")
    assert_equal "failed", preview.status
    assert_nil preview.file_data
  ensure
    file&.close!
  end

  test "pdf preview still marks failed when cleanup delete raises after enqueue failure" do
    file = Tempfile.new([ "gec_preview_enqueue_cleanup_failure", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(
      S3Service,
      enabled?: true,
      upload: ->(key, _data, **_kwargs) { key },
      delete: ->(*_args, **_kwargs) { raise StandardError, "s3 delete exploded" }
    ) do
      with_singleton_stubs(GecPdfPreviewJob, perform_later: ->(*_args, **_kwargs) { raise StandardError, "queue unavailable" }) do
        assert_no_enqueued_jobs only: GecPdfPreviewJob do
          post "/api/v1/gec_voters/preview",
            params: {
              file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
              preview_request_id: "preview-enqueue-cleanup-failure-1"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "preview-enqueue-cleanup-failure-1", json["preview_request_id"]
    assert_equal "failed", json["status"]
    assert_match(/Failed to queue PDF preview: queue unavailable/, json["error"])

    preview = GecPdfPreview.find_by!(preview_request_id: "preview-enqueue-cleanup-failure-1")
    assert_equal "failed", preview.status
    assert_nil preview.file_data
    assert_equal "gec-pdf-previews/preview-enqueue-cleanup-failure-1/source/gec_list.pdf", preview.file_s3_key
  ensure
    file&.close!
  end

  test "pdf preview preserves s3 key when cleanup delete returns false after enqueue failure" do
    file = Tempfile.new([ "gec_preview_enqueue_cleanup_false", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(
      S3Service,
      enabled?: true,
      upload: ->(key, _data, **_kwargs) { key },
      delete: false
    ) do
      with_singleton_stubs(GecPdfPreviewJob, perform_later: ->(*_args, **_kwargs) { raise StandardError, "queue unavailable" }) do
        assert_no_enqueued_jobs only: GecPdfPreviewJob do
          post "/api/v1/gec_voters/preview",
            params: {
              file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
              preview_request_id: "preview-enqueue-cleanup-false-1"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :success
    preview = GecPdfPreview.find_by!(preview_request_id: "preview-enqueue-cleanup-false-1")
    assert_equal "failed", preview.status
    assert_nil preview.file_data
    assert_equal "gec-pdf-previews/preview-enqueue-cleanup-false-1/source/gec_list.pdf", preview.file_s3_key
  ensure
    file&.close!
  end

  test "pdf preview returns clean error when s3 upload fails" do
    file = Tempfile.new([ "gec_preview_s3_failure", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(S3Service, enabled?: true, upload: nil) do
      assert_no_enqueued_jobs only: GecPdfPreviewJob do
        post "/api/v1/gec_voters/preview",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
            preview_request_id: "preview-s3-failure-1"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_match(/Failed to store PDF preview upload/, json["error"])
    assert_nil GecPdfPreview.find_by(preview_request_id: "preview-s3-failure-1")
  ensure
    file&.close!
  end

  test "pdf preview preserves original storage error when storage setup raises before attrs are returned" do
    file = Tempfile.new([ "gec_preview_s3_raise", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    error = assert_raises(StandardError) do
      with_singleton_stubs(
        S3Service,
        enabled?: true,
        upload: ->(*_args, **_kwargs) { raise StandardError, "upload exploded" }
      ) do
        post "/api/v1/gec_voters/preview",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "gec_list.pdf"),
            preview_request_id: "preview-s3-raise-1"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_equal "upload exploded", error.message
    assert_nil GecPdfPreview.find_by(preview_request_id: "preview-s3-raise-1")
  ensure
    file&.close!
  end

  test "pdf preview rejects empty pdf uploads cleanly when s3 is disabled" do
    file = Tempfile.new([ "gec_preview_empty", ".pdf" ])
    file.binmode
    file.rewind

    with_singleton_stubs(S3Service, enabled?: false) do
      assert_no_enqueued_jobs only: GecPdfPreviewJob do
        assert_no_difference("GecPdfPreview.count") do
          post "/api/v1/gec_voters/preview",
            params: {
              file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "empty.pdf"),
              preview_request_id: "preview-empty-pdf-1"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/Uploaded PDF preview is empty/, json["error"])
  ensure
    file&.close!
  end

  test "async pdf upload queues immediately without parsing in controller" do
    file = Tempfile.new([ "gec_async_pdf", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(S3Service, enabled?: false) do
      with_singleton_stubs(GecPdfParserService, new: ->(*_args, **_kwargs) { raise "controller should not parse async pdf uploads" }) do
        assert_enqueued_jobs 1, only: GecImportJob do
          post "/api/v1/gec_voters/upload",
            params: {
              file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "voter_list.pdf"),
              gec_list_date: "2026-02-25",
              async_import: "true",
              confirm_review: "true"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    imp = GecImport.find(json["import"]["id"])
    payload = GecImportUpload.find_by!(gec_import_id: imp.id)

    assert_equal "voter_list.csv", imp.filename
    assert_equal "voter_list.pdf", payload.filename
    assert_equal "application/pdf", payload.content_type
    assert_equal "queued", imp.metadata["stage"]
    assert_equal Rails.application.config.active_job.queue_adapter.to_s, imp.metadata["queue_backend"]
    assert imp.metadata["active_job_id"].present?
    assert imp.metadata["enqueued_at"].present?
  ensure
    file&.close!
  end

  test "async pdf upload ignores provided sheet name" do
    file = Tempfile.new([ "gec_async_pdf_sheet_name", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(S3Service, enabled?: false) do
      with_singleton_stubs(GecPdfParserService, new: ->(*_args, **_kwargs) { raise "controller should not parse async pdf uploads" }) do
        assert_enqueued_jobs 1, only: GecImportJob do
          post "/api/v1/gec_voters/upload",
            params: {
              file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "voter_list.pdf"),
              gec_list_date: "2026-02-25",
              async_import: "true",
              confirm_review: "true",
              sheet_name: "Jan GEC List Test"
            },
            headers: auth_headers(@admin)
        end
      end
    end

    assert_response :accepted
    job = enqueued_jobs.last
    assert_equal "GecImportJob", job[:job].to_s
    assert_nil job[:args].first[:sheet_name]
  ensure
    file&.close!
  end

  test "async pdf upload requires explicit review confirmation before queueing" do
    file = Tempfile.new([ "gec_async_pdf_review", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    with_singleton_stubs(S3Service, enabled?: false) do
      assert_no_enqueued_jobs only: GecImportJob do
        post "/api/v1/gec_voters/upload",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "voter_list.pdf"),
            gec_list_date: "2026-02-25",
            async_import: "true"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "pdf_review_confirmation_required", json["code"]
    assert_match(/Confirm review before starting the background import/i, json["error"])
  ensure
    file&.close!
  end

  test "sync pdf upload preserves normalized csv artifact" do
    file = Tempfile.new([ "gec_sync_pdf", ".pdf" ])
    file.binmode
    file.write("%PDF-1.4 sample")
    file.rewind

    parsed_result = GecPdfParserService::Result.new(
      rows: [
        {
          "name" => "CRUZ, JUAN",
          "village" => "Barrigada",
          "voter_registration_number" => "VR001",
          "dob" => "03/15/1985",
          "dob_estimated" => false,
          "birth_year" => "1985",
          "pct" => "1",
          "address" => "123 TEST ST"
        }
      ],
      qa: { status: "pass", row_count: 1, page_count: 1 },
      warnings: [],
      errors: []
    )

    parser = Object.new
    parser.define_singleton_method(:parse) { parsed_result }
    parser.define_singleton_method(:write_normalized_csv) do |rows|
      tf = Tempfile.new([ "normalized_pdf", ".csv" ])
      CSV.open(tf.path, "w") do |csv|
        csv << [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ]
        rows.each { |r| csv << [ r["name"], r["village"], r["voter_registration_number"], r["dob"], r["dob_estimated"], r["birth_year"], r["pct"], r["address"] ] }
      end
      tf
    end

    uploaded = []
    upload = lambda do |key, data, **kwargs|
      body = data.respond_to?(:read) ? data.read : data
      data.rewind if data.respond_to?(:rewind)
      uploaded << { key: key, data: body, kwargs: kwargs }
      key
    end

    with_singleton_stubs(GecPdfParserService, new: parser) do
      with_singleton_stubs(S3Service, enabled?: true, upload: upload) do
        post "/api/v1/gec_voters/upload",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/pdf", original_filename: "voter_list.pdf"),
            gec_list_date: "2026-02-25",
            async_import: "false",
            confirm_review: "true"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :created
    artifact_upload = uploaded.find { |entry| entry[:key].include?("/artifact/") }
    refute_nil artifact_upload
    assert_equal "text/csv", artifact_upload[:kwargs][:content_type]
    assert_includes artifact_upload[:key], "voter_list.csv"
    assert_includes artifact_upload[:data], "name,village,voter_registration_number,dob,dob_estimated,birth_year,pct,address"
  ensure
    file&.close!
  end

  test "view_import_data returns parsed spreadsheet preview for existing import" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ],
      [ "Maria", "Santos", "Dededo", "VR002" ]
    ])

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 2,
      original_file_s3_key: "gec-imports/1/artifact/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    with_singleton_stubs(S3Service, download: File.binread(file.path)) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data", headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "spreadsheet", json["preview"]["source_type"]
    assert_equal 2, json["preview"]["row_count"]
    assert_equal 1, json["preview"]["pagination"]["page"]
    assert_equal 2, json["preview"]["pagination"]["total_rows"]
    assert_equal "Juan", json["preview"]["preview_rows"][0]["first_name"]
  ensure
    file&.close!
  end

  test "view_import_data paginates parsed rows" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ],
      [ "Maria", "Santos", "Dededo", "VR002" ],
      [ "Pedro", "Reyes", "Yigo", "VR003" ]
    ])

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 3,
      original_file_s3_key: "gec-imports/1/artifact/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    with_singleton_stubs(S3Service, download: File.binread(file.path)) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data",
        params: { page: 2, per_page: 1 },
        headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 2, json["preview"]["pagination"]["page"]
    assert_equal 3, json["preview"]["pagination"]["total_pages"]
    assert_equal 1, json["preview"]["preview_rows"].length
    assert_equal "Maria", json["preview"]["preview_rows"][0]["first_name"]
  ensure
    file&.close!
  end

  test "view_import_data supports search and village filters" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ],
      [ "Maria", "Santos", "Dededo", "VR002" ],
      [ "Pedro", "Reyes", "Dededo", "VR003" ]
    ])

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 3,
      original_file_s3_key: "gec-imports/1/artifact/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    with_singleton_stubs(S3Service, download: File.binread(file.path)) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data",
        params: { q: "pedro", village: "Dededo" },
        headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ "Barrigada", "Dededo" ], json["preview"]["available_villages"]
    assert_equal 1, json["preview"]["pagination"]["total_rows"]
    assert_equal "Pedro", json["preview"]["preview_rows"][0]["first_name"]
  ensure
    file&.close!
  end

  test "view_import_data returns address for parsed pdf imports" do
    file = Tempfile.new([ "gec_pdf_artifact", ".csv" ])
    CSV.open(file.path, "w") do |csv|
      csv << [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ]
      csv << [ "BARCINAS, ROBERT JAMES L.", "Tamuning", "VR001", nil, true, "2000", "19", "434A GAYINERO DR" ]
    end

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_feb_2026.csv",
      status: "completed",
      total_records: 1,
      original_file_s3_key: "gec-imports/1/artifact/gec_feb_2026.csv",
      original_filename: "gec_feb_2026.csv",
      metadata: { "pdf_qa" => { "status" => "pass", "row_count" => 1, "page_count" => 1 } }
    )

    with_singleton_stubs(S3Service, download: File.binread(file.path)) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data", headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "pdf", json["preview"]["source_type"]
    assert_equal "434A GAYINERO DR", json["preview"]["preview_rows"][0]["address"]
    assert_equal "Tamuning", json["preview"]["preview_rows"][0]["village"]
  ensure
    file&.close!
  end

  test "view_import_data caches parsed viewer rows across requests" do
    skip "Test environment cache store does not persist viewer cache" if Rails.cache.class.name.include?("NullStore")

    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ],
      [ "Maria", "Santos", "Dededo", "VR002" ]
    ])

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 2,
      original_file_s3_key: "gec-imports/1/artifact/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    download_count = 0
    downloader = lambda do |_key|
      download_count += 1
      File.binread(file.path)
    end

    Rails.cache.clear
    with_singleton_stubs(S3Service, download: downloader) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data",
        params: { page: 1, per_page: 1 },
        headers: auth_headers(@admin)
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_data",
        params: { page: 2, per_page: 1 },
        headers: auth_headers(@admin)
    end

    assert_equal 1, download_count
  ensure
    Rails.cache.clear
    file&.close!
  end

  test "view_import_changes returns persisted change rows with counts" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 3,
      new_records: 1,
      updated_records: 1,
      removed_records: 1
    )

    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "new",
      first_name: "Juan",
      last_name: "Cruz",
      village_name: "Barrigada",
      voter_registration_number: "VR001"
    )
    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "updated",
      first_name: "Maria",
      last_name: "Santos",
      village_name: "Dededo",
      voter_registration_number: "VR002",
      details: {
        changed_fields: {
          voter_registration_number: {
            before: nil,
            after: "VR002"
          }
        }
      }
    )
    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "removed",
      first_name: "Pedro",
      last_name: "Reyes",
      village_name: "Yigo",
      voter_registration_number: "VR003"
    )

    get "/api/v1/gec_voters/imports/#{gec_import.id}/changes", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 3, json["counts"]["all"]
    assert_equal 1, json["counts"]["new"]
    assert_equal 1, json["counts"]["changed"]
    assert_equal 3, json["pagination"]["total_rows"]
    assert_equal "Pedro", json["changes"].first["first_name"]
  end

  test "view_import_changes filters by changed category and search query" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 2,
      updated_records: 1,
      transferred_records: 1
    )

    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "updated",
      first_name: "Maria",
      last_name: "Santos",
      village_name: "Dededo",
      voter_registration_number: "VR002"
    )
    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "transferred",
      first_name: "Juan",
      last_name: "Cruz",
      village_name: "Yigo",
      previous_village_name: "Barrigada",
      voter_registration_number: "VR001"
    )

    get "/api/v1/gec_voters/imports/#{gec_import.id}/changes",
      params: { type: "changed", q: "juan" },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "changed", json["filters"]["type"]
    assert_equal "juan", json["filters"]["q"]
    assert_equal 1, json["pagination"]["total_rows"]
    assert_equal "transferred", json["changes"].first["change_type"]
  end

  test "view_import_changes clamps requested page to total_pages" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 1,
      new_records: 1
    )

    GecImportChange.create!(
      gec_import: gec_import,
      change_type: "new",
      first_name: "Juan",
      last_name: "Cruz",
      village_name: "Barrigada",
      voter_registration_number: "VR001"
    )

    get "/api/v1/gec_voters/imports/#{gec_import.id}/changes",
      params: { page: 999, per_page: 100 },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["pagination"]["total_pages"]
    assert_equal 1, json["pagination"]["page"]
    assert_equal 1, json["changes"].length
  end

  test "view_import_changes exposes routed to unassigned rows for transparency" do
    file = Tempfile.new([ "gec_unassigned_changes", ".csv" ])
    CSV.open(file.path, "w") do |csv|
      csv << [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ]
      csv << [ "DOE, JANE", nil, "VR001", "01/01/1987", "true", "1987", "5", "USS EXAMPLE" ]
      csv << [ "CRUZ, JUAN", "Barrigada", "VR002", "01/01/1985", "true", "1985", "1", "123 TEST ST" ]
    end

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_feb_2026.csv",
      status: "completed",
      total_records: 2,
      original_file_s3_key: "gec-imports/1/artifact/gec_feb_2026.csv",
      original_filename: "gec_feb_2026.csv",
      metadata: { "unassigned" => 1 }
    )

    with_singleton_stubs(S3Service, download: File.binread(file.path)) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/changes",
        params: { type: "routed_to_unassigned" },
        headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["counts"]["routed_to_unassigned"]
    assert_equal "routed_to_unassigned", json["filters"]["type"]
    assert_equal 1, json["pagination"]["total_rows"]
    assert_equal "routed_to_unassigned", json["changes"].first["change_type"]
    assert_equal "Unassigned", json["changes"].first["village_name"]
    assert_match(/routed to Unassigned/i, json["changes"].first.dig("details", "reason"))
    assert_equal "Unassigned", json["changes"].first.dig("details", "changed_fields", "village_name", "after")
    assert_nil json["changes"].first.dig("details", "changed_fields", "village_name", "before")
    assert_equal "DOE, JANE", json["changes"].first.dig("details", "source_name")
  ensure
    Rails.cache.clear
    file&.close!
  end

  test "view_import_skipped_rows returns persisted skipped rows with counts" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_feb_2026.xlsx",
      status: "completed",
      total_records: 3
    )

    GecImportSkippedRow.create!(
      gec_import: gec_import,
      row_number: 4,
      message: "missing first_name or last_name",
      last_name: "CRUZ",
      village_name: "Barrigada",
      birth_year: 1985,
      raw_values: [ "CRUZ, JUAN", "Barrigada", "1985" ]
    )
    GecImportSkippedRow.create!(
      gec_import: gec_import,
      row_number: 5,
      message: "missing first_name or last_name",
      first_name: "MARIA",
      village_name: "Barrigada",
      birth_year: 1990,
      resolution_status: "dismissed",
      resolution_action: "dismiss",
      resolved_at: Time.current,
      resolved_by_user: @admin
    )

    get "/api/v1/gec_voters/imports/#{gec_import.id}/skipped_rows", headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 2, json["counts"]["all"]
    assert_equal 1, json["counts"]["pending"]
    assert_equal 1, json["counts"]["dismissed"]
    assert_equal 2, json["import"]["skipped_rows_count"]
    assert_equal 5, json["skipped_rows"].first["row_number"]
  end

  test "resolve_skipped_row previews and applies audited update" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_feb_2026.xlsx",
      status: "completed",
      total_records: 1
    )

    skipped_row = GecImportSkippedRow.create!(
      gec_import: gec_import,
      row_number: 6,
      message: "missing first_name or last_name",
      village_name: "Barrigada",
      birth_year: 1985
    )

    post "/api/v1/gec_voters/imports/#{gec_import.id}/skipped_rows/#{skipped_row.id}/preview_resolution",
      params: {
        corrected_values: {
          first_name: "Juan",
          last_name: "Cruz",
          village_name: "Dededo",
          dob: "1985-03-15"
        },
        selected_gec_voter_id: @gec_voter.id
      },
      headers: auth_headers(@admin)

    assert_response :success
    preview_json = JSON.parse(response.body)
    assert_equal "ready_to_update", preview_json["preview"]["status"]
    assert_equal "update", preview_json["preview"]["suggested_action"]

    post "/api/v1/gec_voters/imports/#{gec_import.id}/skipped_rows/#{skipped_row.id}/resolve",
      params: {
        corrected_values: {
          first_name: "Juan",
          last_name: "Cruz",
          village_name: "Dededo",
          dob: "1985-03-15"
        },
        selected_gec_voter_id: @gec_voter.id
      },
      headers: auth_headers(@admin)

    assert_response :success
    json = JSON.parse(response.body)
    skipped_row.reload
    @gec_voter.reload

    assert_equal "resolved_updated", skipped_row.resolution_status
    assert_equal "Dededo", @gec_voter.village_name
    assert_equal "resolved_updated", json["skipped_row"]["resolution_status"]
    assert_equal 1, AuditLog.where(auditable: skipped_row, action: "gec_import_skipped_row_resolved").count
  end

  test "view_original returns inline viewer metadata for preserved raw pdf" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.csv",
      status: "completed",
      total_records: 50000,
      raw_file_s3_key: "gec-imports/1/raw/gec_jan_2026.pdf",
      raw_filename: "gec_jan_2026.pdf",
      raw_content_type: "application/pdf"
    )

    calls = []
    presign = lambda do |key, **kwargs|
      calls << { key: key, kwargs: kwargs }
      "https://example.test/original.pdf"
    end

    with_singleton_stubs(S3Service, presigned_url: presign) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/view_original", headers: auth_headers(@admin)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["inline_supported"]
    assert_equal "application/pdf", json["content_type"]
    assert_equal 1800, calls.first[:kwargs][:expires_in]
  end

  test "download_import prefers raw file when available" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.csv",
      status: "completed",
      total_records: 50000,
      raw_file_s3_key: "gec-imports/1/raw/gec_jan_2026.pdf",
      raw_filename: "gec_jan_2026.pdf",
      original_file_s3_key: "gec-imports/1/artifact/gec_jan_2026.csv",
      original_filename: "gec_jan_2026.csv"
    )

    calls = []
    presign = lambda do |key, **kwargs|
      calls << { key: key, kwargs: kwargs }
      "https://example.test/download"
    end

    with_singleton_stubs(S3Service, presigned_url: presign) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/download", headers: auth_headers(@admin)
    end

    assert_response :success
    assert_equal "gec-imports/1/raw/gec_jan_2026.pdf", calls.first[:key]
  end

  test "async upload preserves raw file metadata and import artifact" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ]
    ])

    uploaded_keys = []
    upload = lambda do |key, _data, **_kwargs|
      uploaded_keys << key
      key
    end

    with_singleton_stubs(S3Service, enabled?: true, upload: upload) do
      perform_enqueued_jobs do
        post "/api/v1/gec_voters/upload",
          params: {
            file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "gec_upload.xlsx"),
            gec_list_date: "2026-02-25",
            async_import: "true",
            upload_request_id: "req-gec-upload-1"
          },
          headers: auth_headers(@admin)
      end
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    imp = GecImport.find(json["import"]["id"])
    assert_equal "gec_upload.xlsx", imp.raw_filename
    assert imp.raw_file_s3_key.present?
    assert imp.original_file_s3_key.present?
    assert_equal "background", imp.metadata["mode"]
    assert_equal "req-gec-upload-1", imp.metadata["upload_request_id"]
    assert uploaded_keys.any? { |key| key.include?("/raw/") }
    assert uploaded_keys.any? { |key| key.include?("/artifact/") }
  ensure
    file&.close!
  end

  test "async upload request id is idempotent across duplicate retries" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ]
    ])

    request_id = "req-gec-dedupe-1"
    first_import_id = nil

    with_singleton_stubs(S3Service, enabled?: false) do
      assert_difference("GecImport.count", 1) do
        assert_difference("GecImportUpload.count", 1) do
          assert_enqueued_jobs 1, only: GecImportJob do
            post "/api/v1/gec_voters/upload",
              params: {
                file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "gec_upload.xlsx"),
                gec_list_date: "2026-02-25",
                async_import: "true",
                upload_request_id: request_id
              },
              headers: auth_headers(@admin)

            assert_response :accepted
            first_json = JSON.parse(response.body)
            first_import_id = first_json.dig("import", "id")
            assert_nil first_json["duplicate_request"]

            post "/api/v1/gec_voters/upload",
              params: {
                file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "gec_upload.xlsx"),
                gec_list_date: "2026-02-25",
                async_import: "true",
                upload_request_id: request_id
              },
              headers: auth_headers(@admin)

            assert_response :accepted
            duplicate_json = JSON.parse(response.body)
            assert_equal true, duplicate_json["duplicate_request"]
            assert_equal first_import_id, duplicate_json.dig("import", "id")
          end
        end
      end
    end
  ensure
    file&.close!
  end

  test "async upload retries can recover a pending import without an enqueued job id" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village", "Reg No" ],
      [ "Juan", "Cruz", "Barrigada", "VR001" ]
    ])

    existing_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_upload.xlsx",
      uploaded_by_user: @admin,
      import_type: "full_list",
      status: "pending",
      metadata: {
        "stage" => "queued",
        "progress_percent" => 0,
        "mode" => "background",
        "upload_request_id" => "req-gec-retry-1"
      }
    )

    with_singleton_stubs(S3Service, enabled?: false) do
      assert_no_difference("GecImport.count") do
        assert_difference("GecImportUpload.count", 1) do
          assert_enqueued_jobs 1, only: GecImportJob do
            post "/api/v1/gec_voters/upload",
              params: {
                file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "gec_upload.xlsx"),
                gec_list_date: "2026-02-25",
                async_import: "true",
                upload_request_id: "req-gec-retry-1"
              },
              headers: auth_headers(@admin)
          end
        end
      end
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal existing_import.id, json.dig("import", "id")
    existing_import.reload
    assert existing_import.metadata["active_job_id"].present?
    assert existing_import.upload_payload.present?
  ensure
    file&.close!
  end

  test "download_import returns service_unavailable when S3 not configured" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 50000,
      original_file_s3_key: "gec-imports/1/gec_jan_2026.xlsx",
      original_filename: "gec_jan_2026.xlsx"
    )

    with_singleton_stubs(S3Service, presigned_url: nil) do
      get "/api/v1/gec_voters/imports/#{gec_import.id}/download", headers: auth_headers(@admin)
    end

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_equal "s3_error", json["code"]
  end

  test "download_import returns 404 when no original file" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 1, 25),
      filename: "gec_jan_2026.xlsx",
      status: "completed",
      total_records: 50000
    )

    get "/api/v1/gec_voters/imports/#{gec_import.id}/download", headers: auth_headers(@admin)

    assert_response :not_found
  end

  private

  def create_test_excel(rows)
    file = Tempfile.new([ "gec_test", ".xlsx" ])
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Voters") do |sheet|
      rows.each { |row| sheet.add_row(row) }
    end
    package.serialize(file.path)
    file
  end

  def with_singleton_stubs(klass, stubs)
    singleton = class << klass; self; end
    originals = {}

    stubs.each do |method_name, replacement|
      originals[method_name] = singleton.instance_method(method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name) do |*args, **kwargs, &block|
        if replacement.respond_to?(:call)
          replacement.call(*args, **kwargs, &block)
        else
          replacement
        end
      end
    end

    yield
  ensure
    stubs.each_key do |method_name|
      singleton.send(:remove_method, method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name, originals[method_name]) if originals[method_name]
    end
  end
end
