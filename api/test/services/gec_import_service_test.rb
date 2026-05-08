require "test_helper"
require "tempfile"
require "csv"

class GecImportServiceTest < ActiveSupport::TestCase
  setup do
    @village = Village.find_or_create_by!(name: "Barrigada")
    Village.find_or_create_by!(name: "Dededo")
  end

  test "parses Excel file and creates GEC voters" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Barrigada", "VR001" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ],
      [ "Pedro", "Reyes", Date.new(1975, 11, 8), "Dededo", "VR003" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    result = service.call

    assert result.success, "Import should succeed. Errors: #{result.errors}"
    assert_equal 3, result.stats[:total]
    assert_equal 3, result.stats[:new]
    assert_equal 0, result.stats[:updated]

    assert_equal 3, GecVoter.count
    juan = GecVoter.find_by(first_name: "Juan", last_name: "Cruz")
    assert_equal Date.new(1985, 3, 15), juan.dob
    assert_equal "Barrigada", juan.village_name
    assert_equal @village.id, juan.village_id
  end

  test "persists imported GEC address data" do
    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, JUAN", "Barrigada", "VR001", "03/15/1985", "false", "1985", "1", "123 TEST ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    voter = GecVoter.find_by!(voter_registration_number: "VR001")
    assert_equal "123 TEST ST", voter.address
  ensure
    file&.close!
  end

  test "persists imported GEC precinct number and resolves precinct association" do
    precinct = Precinct.create!(village: @village, number: "19", alpha_range: "A-Z")
    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, JUAN", "Barrigada", "VR001", "03/15/1985", "false", "1985", "19", "123 TEST ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    voter = GecVoter.find_by!(voter_registration_number: "VR001")
    assert_equal "19", voter.precinct_number
    assert_equal precinct.id, voter.precinct_id
  ensure
    file&.close!
  end

  test "canonicalizes imported village aliases onto existing village records" do
    humatak = Village.find_or_create_by!(name: "Humåtak")
    malesso = Village.find_or_create_by!(name: "Malesso'")
    mtm = Village.find_or_create_by!(name: "Mongmong/Toto/Maite")

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, JUAN", "HUMATAK", "VR001", "01/01/1985", "true", "1985", "1", "123 TEST ST" ],
      [ "SANTOS, MARIA", "MALESSO", "VR002", "01/01/1990", "true", "1990", "2", "456 TEST ST" ],
      [ "PEREZ, PATRINA", "MONGMONG", "VR003", "01/01/1984", "true", "1984", "8A", "116 PETMANENTE ST" ],
      [ "GILL, LILLIAN", "TOTO", "VR004", "01/01/1995", "true", "1995", "6", "166 CHALAN RS SANCHEZ" ],
      [ "GURWELL, DANNY", "MAITE", "VR005", "01/01/1964", "true", "1964", "11A", "472 RT 8 STE 1B-496" ],
      [ "APIAG, RAPHON", "MTM", "VR006", "01/01/1982", "true", "1982", "8A", "123 TEST ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success

    juan = GecVoter.find_by!(voter_registration_number: "VR001")
    maria = GecVoter.find_by!(voter_registration_number: "VR002")
    pat = GecVoter.find_by!(voter_registration_number: "VR003")
    lillian = GecVoter.find_by!(voter_registration_number: "VR004")
    danny = GecVoter.find_by!(voter_registration_number: "VR005")
    raphon = GecVoter.find_by!(voter_registration_number: "VR006")

    assert_equal "Humåtak", juan.village_name
    assert_equal humatak.id, juan.village_id
    assert_equal "Malesso'", maria.village_name
    assert_equal malesso.id, maria.village_id
    assert_equal "Mongmong/Toto/Maite", pat.village_name
    assert_equal mtm.id, pat.village_id
    assert_equal "Mongmong/Toto/Maite", lillian.village_name
    assert_equal mtm.id, lillian.village_id
    assert_equal "Mongmong/Toto/Maite", danny.village_name
    assert_equal mtm.id, danny.village_id
    assert_equal "Mongmong/Toto/Maite", raphon.village_name
    assert_equal mtm.id, raphon.village_id
  ensure
    file&.close!
  end

  test "updates existing voters on re-import" do
    GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Barrigada", "VR001-NEW" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    result = service.call

    assert result.success
    assert_equal 1, result.stats[:updated]
    assert_equal 0, result.stats[:new]
    assert_equal 1, GecVoter.count

    juan = GecVoter.first
    assert_equal Date.new(2026, 2, 25), juan.gec_list_date
    assert_equal "VR001-NEW", juan.voter_registration_number
  end

  test "detects ambiguous DOB" do
    # March 5 — both month (3) and day (5) are ≤ 12, could be May 3
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village" ],
      [ "Ana", "Flores", Date.new(1988, 3, 5), "Barrigada" ],
      [ "Ben", "Torres", Date.new(1992, 6, 25), "Barrigada" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    result = service.call

    assert result.success
    ana = GecVoter.find_by(first_name: "Ana")
    ben = GecVoter.find_by(first_name: "Ben")

    assert ana.dob_ambiguous, "Ana's DOB (March 5) should be flagged as ambiguous"
    refute ben.dob_ambiguous, "Ben's DOB (June 25) should NOT be ambiguous (day > 12)"
    assert_equal 1, result.stats[:ambiguous_dob]
  end

  test "skips rows with missing required fields" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village" ],
      [ "Juan", "Cruz", "Barrigada" ],
      [ "", "Santos", "Barrigada" ],
      [ "Pedro", "", "Barrigada" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    result = service.call

    assert result.success
    assert_equal 1, result.stats[:new]
    assert_equal 2, result.stats[:skipped]
    assert_equal 2, result.gec_import.metadata["row_error_details"].length
    assert_equal "missing first_name or last_name", result.gec_import.metadata["row_error_details"].first["message"]
    assert_equal 2, result.gec_import.skipped_rows.count
    assert_equal [ 3, 4 ], result.gec_import.skipped_rows.order(:row_number).pluck(:row_number)
  end

  test "skips ambiguous exact matches instead of updating an arbitrary active voter" do
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "FLORES",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "FLORES",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR002",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, MARIE FLORES", "Tamuning", "VR999", "01/01/1955", "true", "1955", "4", "PO BOX 123" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:skipped]
    assert_equal 0, result.stats[:updated]
    assert_equal 0, result.stats[:transferred]
    assert_match(/ambiguous exact match/i, result.gec_import.metadata["row_error_details"].first["message"])
    assert_equal %w[VR001 VR002], GecVoter.active.where(first_name: "MARIE", last_name: "CRUZ", village_name: "Tamuning", birth_year: 1955).order(:voter_registration_number).pluck(:voter_registration_number)
  ensure
    file&.close!
  end

  test "preserves middle names from combined GEC name columns" do
    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "ADAMS, ISABEL ANN", "Hagatna", "VR-MIDDLE-1", "01/01/1987", "true", "1987", "1", "147 9TH ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    voter = GecVoter.find_by!(voter_registration_number: "VR-MIDDLE-1")
    assert_equal "ISABEL", voter.first_name
    assert_equal "ANN", voter.middle_name
    assert_equal "ADAMS", voter.last_name
  ensure
    file&.close!
  end

  test "skips ambiguous transfer matches instead of silently moving a voter" do
    GecVoter.create!(
      first_name: "JOSEPH",
      last_name: "CRUZ",
      village_name: "Malesso'",
      birth_year: 1967,
      voter_registration_number: "VR100",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "JOSEPH",
      last_name: "CRUZ",
      village_name: "Barrigada",
      birth_year: 1967,
      voter_registration_number: "VR200",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, JOSEPH B", "Hagåtña", "VR300", "01/01/1967", "true", "1967", "9", "PO BOX 555" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:skipped]
    assert_equal 0, result.stats[:new]
    assert_equal 0, result.stats[:updated]
    assert_equal 0, result.stats[:transferred]
    assert_match(/ambiguous transfer match/i, result.gec_import.metadata["row_error_details"].first["message"])
  ensure
    file&.close!
  end

  test "ignores removed historical voters when matching current import rows" do
    GecVoter.create!(
      first_name: "EILEEN",
      middle_name: "C.",
      last_name: "SANCHEZ",
      village_name: "Hågat",
      birth_year: 1973,
      voter_registration_number: "VR-ACTIVE",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "EILEEN",
      middle_name: "C.",
      last_name: "SANCHEZ",
      village_name: "Hågat",
      birth_year: 1973,
      voter_registration_number: "VR-REMOVED",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 2.months.ago,
      status: "removed",
      removed_at: 1.month.ago
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "SANCHEZ, EILEEN C.", "Agat", "VR-ACTIVE", "01/01/1973", "true", "1973", "4A", "PO BOX 8608" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:matched_unchanged]
    assert_equal 1, result.stats[:updated]
    assert_equal 0, result.stats[:skipped]
    assert_equal "removed", GecVoter.find_by(voter_registration_number: "VR-REMOVED").status
    assert_equal "active", GecVoter.find_by(voter_registration_number: "VR-ACTIVE").status
  ensure
    file&.close!
  end

  test "skips malformed parsed source names without a comma" do
    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "N MARINE CORPS DR", "Hagatna", "", "01/01/1983", "true", "1983", "10", "PO BOX 1" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:skipped]
    assert_match(/malformed source name/i, result.gec_import.metadata["row_error_details"].first["message"])
  ensure
    file&.close!
  end

  test "creates distinct voters when source identity collisions have unique vrns" do
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "FLORES",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, MARIE FLORES", "Tamuning", "VR001", "01/01/1955", "true", "1955", "4", "PO BOX 1" ],
      [ "CRUZ, MARIE MENDIOLA", "Hagåtña", "VR002", "01/01/1955", "true", "1955", "1", "PO BOX 2" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:matched_unchanged]
    assert_equal 1, result.stats[:new]
    assert_equal 0, result.stats[:skipped]
    assert_equal 1, result.stats[:updated]
    assert_equal 0, result.stats[:transferred]
    assert_nil result.gec_import.metadata["row_error_details"].presence

    assert_equal %w[VR001 VR002], GecVoter.active.where(first_name: "MARIE", last_name: "CRUZ", birth_year: 1955).order(:voter_registration_number).pluck(:voter_registration_number)
  ensure
    file&.close!
  end

  test "allows source identity collisions when each row has a unique trusted vrn match" do
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "FLORES",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "MENDIOLA",
      last_name: "CRUZ",
      village_name: "Hagåtña",
      birth_year: 1955,
      voter_registration_number: "VR002",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, MARIE FLORES", "Tamuning", "VR001", "01/01/1955", "true", "1955", "4", "PO BOX 1" ],
      [ "CRUZ, MARIE MENDIOLA", "Hagåtña", "VR002", "01/01/1955", "true", "1955", "1", "PO BOX 2" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:matched_unchanged]
    assert_equal 2, result.stats[:updated]
    assert_equal 0, result.stats[:skipped]
    assert_nil result.gec_import.metadata["row_error_details"].presence
  ensure
    file&.close!
  end

  test "skips rows when source identity collisions cannot be resolved by vrn" do
    GecVoter.create!(
      first_name: "MARIE",
      middle_name: "FLORES",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, MARIE FLORES", "Tamuning", "VR001", "01/01/1955", "true", "1955", "4", "PO BOX 1" ],
      [ "CRUZ, MARIE MENDIOLA", "Hagåtña", "", "01/01/1955", "true", "1955", "1", "PO BOX 2" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:matched_unchanged]
    assert_equal 1, result.stats[:updated]
    assert_equal 1, result.stats[:skipped]
    assert_match(/ambiguous source identity/i, result.gec_import.metadata["row_error_details"].first["message"])
  ensure
    file&.close!
  end

  test "full_list import suppresses removals when skipped rows require review" do
    GecVoter.create!(
      first_name: "MARIE",
      last_name: "CRUZ",
      village_name: "Tamuning",
      birth_year: 1955,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "MARIE",
      last_name: "CRUZ",
      village_name: "Hagåtña",
      birth_year: 1955,
      voter_registration_number: "VR002",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    untouched = GecVoter.create!(
      first_name: "PEDRO",
      last_name: "SANTOS",
      village_name: "Dededo",
      birth_year: 1980,
      voter_registration_number: "VR999",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, MARIE FLORES", "Tamuning", "VR001", "01/01/1955", "true", "1955", "4", "PO BOX 1" ],
      [ "CRUZ, MARIE MENDIOLA", "Hagåtña", "", "01/01/1955", "true", "1955", "1", "PO BOX 2" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 1, result.stats[:skipped]
    assert_equal 0, result.stats[:removed]
    assert_equal true, result.gec_import.metadata["removal_detection_suppressed"]
    assert_equal true, result.gec_import.metadata["review_required"]

    untouched.reload
    assert_equal "active", untouched.status
  ensure
    file&.close!
  end

  test "pdf-style birth-year import matches existing voter by vrn and canonical village" do
    Village.find_or_create_by!(name: "Hagåtña")
    existing = GecVoter.create!(
      first_name: "ADRIAN",
      last_name: "ALDRIDGE",
      dob: Date.new(1947, 5, 10),
      birth_year: 1947,
      village_name: "Hagåtña",
      voter_registration_number: "24688",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "ALDRIDGE, ADRIAN", "HAGATNA", "24688", "01/01/1947", "true", "1947", "1", "133 OLIAZ ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 1, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:new]
    assert_equal 1, result.stats[:updated]
    assert_equal 0, result.stats[:matched_unchanged]
    assert_equal 1, GecVoter.where(status: "active").count

    existing.reload
    assert_equal "Hagåtña", existing.village_name
    assert_equal Date.new(1947, 5, 10), existing.dob
    assert_equal 1947, existing.birth_year
  ensure
    file&.close!
  end

  test "preloads voter registration matches in a single query per import" do
    GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      village_name: "Barrigada",
      birth_year: 1985,
      voter_registration_number: "VR001",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    GecVoter.create!(
      first_name: "Maria",
      last_name: "Santos",
      village_name: "Dededo",
      birth_year: 1990,
      voter_registration_number: "VR002",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, JUAN", "Barrigada", "VR001", "01/01/1985", "true", "1985", "1", "123 TEST ST" ],
      [ "SANTOS, MARIA", "Dededo", "VR002", "01/01/1990", "true", "1990", "2", "456 TEST ST" ]
    ])

    sql = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA"

      sql << payload[:sql]
    end

    result = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      result = GecImportService.new(
        file_path: file.path,
        gec_list_date: Date.new(2026, 1, 25),
        import_type: "changes_only"
      ).call
    end

    assert result.success
    assert_equal 1, sql.grep(/FROM "gec_voters".*"voter_registration_number" IN/i).size
    assert_equal 0, sql.grep(/FROM "gec_voters".*"voter_registration_number" =/i).size
  ensure
    file&.close!
  end

  test "chunks voter registration preload queries for large imports" do
    rows = (1..(GecImportService::VRN_LOOKUP_BATCH_SIZE + 1)).map { |i| [ "VR#{i}" ] }
    sql = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA"

      sql << payload[:sql]
    end

    lookup = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      lookup = GecImportService.new(
        file_path: "/tmp/fake.csv",
        gec_list_date: Date.new(2026, 1, 25),
        import_type: "changes_only"
      ).send(:build_voter_registration_lookup, rows, { "voter_registration_number" => 0 })
    end

    assert_equal({}, lookup)
    assert_equal 2, sql.grep(/FROM "gec_voters".*"voter_registration_number" (?:IN|=)/i).size
  end

  test "ignores conflicting vrn matches when names do not match" do
    jane = GecVoter.create!(
      first_name: "JANE",
      last_name: "SMITH",
      village_name: "Dededo",
      birth_year: 1980,
      voter_registration_number: "123456",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )
    john = GecVoter.create!(
      first_name: "JOHN",
      last_name: "DOE",
      village_name: "Barrigada",
      birth_year: 1980,
      voter_registration_number: nil,
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "DOE, JOHN", "Barrigada", "123456", "01/01/1980", "true", "1980", "1", "123 TEST ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 1, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:updated]
    assert_equal 0, result.stats[:matched_unchanged]

    jane.reload
    john.reload
    assert_equal "123456", jane.voter_registration_number
    assert_nil john.voter_registration_number
  ensure
    file&.close!
  end

  test "vrn-matched updates persist and report corrected names" do
    existing = GecVoter.create!(
      first_name: "JHON",
      last_name: "DOEE",
      village_name: "Barrigada",
      birth_year: 1980,
      voter_registration_number: "VR123",
      gec_list_date: Date.new(2025, 12, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "DOE, JOHN", "Barrigada", "VR123", "01/01/1980", "true", "1980", "1", "123 TEST ST" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 1, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:updated]

    existing.reload
    assert_equal "JOHN", existing.first_name
    assert_equal "DOE", existing.last_name

    change = result.gec_import.change_records.find_by!(change_type: "updated")
    changed_fields = change.details["changed_fields"]
    assert_equal({ "before" => "JHON", "after" => "JOHN" }, changed_fields["first_name"])
    assert_equal({ "before" => "DOEE", "after" => "DOE" }, changed_fields["last_name"])
  ensure
    file&.close!
  end

  test "vrn match trusts shared name component plus birth year for surname changes" do
    existing = GecVoter.create!(
      first_name: "WANA",
      last_name: "WINTTERLE",
      village_name: "Tamuning",
      birth_year: 1990,
      voter_registration_number: "1879",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "CRUZ, WANA FRANCES D.", "Malesso", "1879", "01/01/1990", "true", "1990", "18B", "PO BOX 9306" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 1, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:new]
    assert_equal 0, result.stats[:updated]
    assert_equal 1, result.stats[:transferred]

    existing.reload
    assert_equal "WANA", existing.first_name
    assert_equal "CRUZ", existing.last_name
    assert_equal "Malesso'", existing.village_name
    assert_equal "1879", existing.voter_registration_number
  ensure
    file&.close!
  end

  test "official GEC combined-name format detects village column instead of address column" do
    Village.find_or_create_by!(name: "Dededo")

    file = create_test_excel([
      [ 16431, "REG. NO.", "NAME", "ADDRESS", nil, nil, "DOB", "PCT" ],
      [ 1, "43881", "ABAD, BRENDA R.", "PMB 932 111 CHALAN BALAKO", "DEDEDO", "GU", Date.new(1975, 11, 16), 18 ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2025, 12, 25)
    )
    preview = service.preview(limit: 5)

    assert_equal "Dededo", preview[:preview_rows][0][:village_name]
    refute_equal "PMB 932 111 CHALAN BALAKO", preview[:preview_rows][0][:village_name]
    assert_equal "PMB 932 111 CHALAN BALAKO", preview[:preview_rows][0][:address]
  ensure
    file&.close!
  end

  test "combined-name fallback does not treat village column as address when address is missing" do
    Village.find_or_create_by!(name: "Dededo")

    file = create_test_excel([
      [ 16431, "REG. NO.", "NAME", nil, nil, "DOB", "PCT" ],
      [ 1, "43881", "ABAD, BRENDA R.", "DEDEDO", "GU", Date.new(1975, 11, 16), 18 ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2025, 12, 25)
    )
    preview = service.preview(limit: 5)

    assert_equal "Dededo", preview[:preview_rows][0][:village_name]
    assert_nil preview[:preview_rows][0][:address]
  ensure
    file&.close!
  end

  test "placeholder NEW registration numbers do not merge unrelated rows" do
    file = create_test_excel([
      [ 16431, "REG. NO.", "NAME", "ADDRESS", nil, nil, "DOB", "PCT", "CONTACT 1", "CONTACT 2", "EMAIL", "NOTES", "Q", "BL SOURCE", "MISC" ],
      [ 1, "NEW", "ADA, ADRIAN ANTHONY T.", nil, nil, nil, Date.new(1980, 3, 28), 9, "NEED CONTACT #", nil, nil, "EARLY VOTED AS OF 10/24/2022", "GE6", nil, nil ],
      [ 1, "NEW", "AFLLEJE, WILLIAM J.", nil, nil, nil, Date.new(1959, 12, 7), 14, "6717881550", nil, nil, "EARLY VOTED ON 10/12/2022", "GE5", nil, nil ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2025, 12, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 2, result.stats[:new]
    assert_equal 0, result.stats[:updated]
    assert_equal 2, GecVoter.count
    assert_equal 0, result.gec_import.change_records.where(change_type: "updated").count

    voters = GecVoter.order(:last_name, :first_name).pluck(:first_name, :last_name, :voter_registration_number, :village_name, :birth_year)
    assert_equal [
      [ "ADRIAN", "ADA", nil, "Unassigned", 1980 ],
      [ "WILLIAM", "AFLLEJE", nil, "Unassigned", 1959 ]
    ], voters
  ensure
    file&.close!
  end

  test "unknown import village names are routed to unassigned" do
    file = create_test_csv([
      [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ],
      [ "TESTER, OFF ISLAND", "FPO", "VR-UNK-1", "01/01/1987", "true", "1987", "5", "USS EXAMPLE" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    voter = GecVoter.find_by!(voter_registration_number: "VR-UNK-1")
    assert_equal "Unassigned", voter.village_name
  ensure
    file&.close!
  end

  test "preview returns sample data without importing" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Barrigada" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    preview = service.preview(limit: 10)

    assert_equal 2, preview[:row_count]
    assert_equal 2, preview[:preview_rows].size
    assert_equal "Juan", preview[:preview_rows][0][:first_name]
    assert_equal 0, GecVoter.count, "Preview should not create records"
  end

  test "parse_birth_year rejects out-of-range Date/DateTime/Time years" do
    service = GecImportService.new(file_path: "/tmp/fake.xlsx", gec_list_date: Date.new(2026, 2, 25))

    assert_nil service.send(:parse_birth_year, Date.new(2099, 1, 1))
    assert_nil service.send(:parse_birth_year, DateTime.new(1899, 1, 1, 0, 0, 0))
    assert_nil service.send(:parse_birth_year, Time.new(2099, 1, 1, 0, 0, 0))
    assert_equal 1985, service.send(:parse_birth_year, Date.new(1985, 7, 1))
  end

  test "creates GecImport record" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village" ],
      [ "Juan", "Cruz", "Barrigada" ]
    ])

    service = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25)
    )

    result = service.call

    assert result.success
    assert_equal 1, GecImport.count
    import = GecImport.first
    assert_equal "completed", import.status
    assert_equal 1, import.total_records
    assert_equal 1, import.new_records
  end

  test "background import stays processing until artifact finalization completes" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Village" ],
      [ "Juan", "Cruz", "Barrigada" ]
    ])

    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "gec_async.xlsx",
      import_type: "full_list",
      status: "processing",
      metadata: { "stage" => "importing", "progress_percent" => 85 }
    )

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      gec_import: gec_import
    ).call

    assert result.success
    gec_import.reload
    assert_equal "processing", gec_import.status
    assert_equal "finalizing_artifact", gec_import.metadata["stage"]
    assert_equal 95, gec_import.metadata["progress_percent"]
    assert_equal 1, gec_import.total_records
    assert_equal 1, gec_import.new_records
  end

  test "full_list import detects purged voters" do
    # Existing voter from last month
    gv = GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )

    # New list does NOT include Juan — only Maria
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 1, result.stats[:removed]
    assert_equal 1, result.stats[:new]

    gv.reload
    assert_equal "removed", gv.status
    assert_not_nil gv.removed_at
  end

  test "stores new and removed change records for a full list import" do
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success

    change_types = result.gec_import.change_records.order(:id).pluck(:change_type)
    assert_equal [ "new", "removed" ], change_types.sort

    removed_change = result.gec_import.change_records.find_by!(change_type: "removed")
    assert_equal "Juan", removed_change.first_name
    assert_equal "missing_from_full_list", removed_change.details["reason"]
  ensure
    file&.close!
  end

  test "changes_only import does not purge missing voters" do
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:removed]
    # Juan should still be active
    assert_equal "active", GecVoter.find_by(first_name: "Juan").status
  end

  test "full_list import detects village transfers" do
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      dob: Date.new(1985, 3, 15), gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago, status: "active"
    )

    # Juan moved to Dededo
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Dededo", "VR001" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 1, result.stats[:transferred]
    assert_equal 0, result.stats[:updated]
    assert_equal 1, result.gec_import.reload.transferred_records
    assert_equal 0, result.gec_import.updated_records

    juan = GecVoter.find_by(first_name: "Juan")
    assert_equal "Dededo", juan.village_name
    assert_equal "Barrigada", juan.previous_village_name
    assert_equal "active", juan.status
  end

  test "stores transfer change details for moved voters" do
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      dob: Date.new(1985, 3, 15), gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago, status: "active"
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Dededo", "VR001" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success

    transfer_change = result.gec_import.change_records.find_by!(change_type: "transferred")
    assert_equal "Dededo", transfer_change.village_name
    assert_equal "Barrigada", transfer_change.previous_village_name
    assert_equal "Barrigada", transfer_change.details["changed_fields"]["village_name"]["before"]
    assert_equal "Dededo", transfer_change.details["changed_fields"]["village_name"]["after"]
  ensure
    file&.close!
  end

  test "birth-year-only transfer fallback does not merge when multiple candidates exist" do
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", birth_year: 1985, village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", birth_year: 1985, village_name: "Dededo",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Birth Year", "Village", "Reg No" ],
      [ "Juan", "Cruz", 1985, "Yigo", "VR001" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:transferred]
    assert_equal 0, result.stats[:new]
    assert_equal 1, result.stats[:skipped]
    assert_match(/ambiguous transfer match/i, result.gec_import.metadata["row_error_details"].first["message"])
    assert_nil GecVoter.find_by(first_name: "Juan", last_name: "Cruz", village_name: "Yigo")
  end

  test "full_list import marks previously verified supporters as no match when voter is removed" do
    # GEC voter
    GecVoter.create!(
      first_name: "Juan", last_name: "Cruz", village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25), imported_at: 1.month.ago, status: "active"
    )

    # Verified supporter matching that voter — use update_columns to bypass auto-vet callback
    village = Village.find_or_create_by!(name: "Barrigada")
    supporter = Supporter.create!(
      first_name: "Juan", last_name: "Cruz", village: village,
      contact_number: "671-555-1234", status: "active",
      source: "staff_entry"
    )
    supporter.update_columns(verification_status: "verified", registered_voter: true)

    # New list without Juan
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 1, result.stats[:re_vetted]

    supporter = Supporter.find_by(first_name: "Juan", last_name: "Cruz")
    assert_equal "unverified", supporter.verification_status
    assert_equal false, supporter.registered_voter
  end

  test "full_list import re-vets active supporters who become newly matched" do
    village = Village.find_or_create_by!(name: "Barrigada")
    supporter = Supporter.create!(
      first_name: "Marissa", last_name: "Public", village: village,
      dob: Date.new(1992, 4, 9),
      contact_number: "671-555-6789", status: "active",
      source: "public_signup", attribution_method: "public_signup"
    )
    supporter.update_columns(verification_status: "unverified", registered_voter: false)

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Marissa", "Public", Date.new(1992, 4, 9), "Barrigada", "VR555" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    assert result.success
    assert_equal 1, result.stats[:re_vetted]

    supporter.reload
    assert_equal "verified", supporter.verification_status
    assert_equal true, supporter.registered_voter
    assert_not_nil supporter.verified_at
  end

  test "tracks matched_unchanged when re-importing identical data" do
    GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      birth_year: 1985,
      village_name: "Barrigada",
      gec_list_date: Date.new(2026, 2, 25),
      imported_at: 1.day.ago
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Barrigada", nil ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:updated], "No fields changed, should not count as updated"
    assert_equal 1, result.stats[:matched_unchanged], "Should count as matched_unchanged"
    assert_equal 1, result.gec_import.metadata["matched_unchanged"]
  end

  test "dob ambiguity only change does not count as updated" do
    GecVoter.create!(
      first_name: "Ana",
      last_name: "Flores",
      dob: Date.new(1988, 3, 5),
      dob_ambiguous: false,
      birth_year: 1988,
      village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago,
      status: "active"
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Ana", "Flores", Date.new(1988, 3, 5), "Barrigada", nil ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 0, result.stats[:updated], "DOB ambiguity-only change should not count as updated"
    assert_equal 1, result.stats[:matched_unchanged]
    assert_equal 0, result.gec_import.change_records.where(change_type: "updated").count

    voter = GecVoter.find_by!(first_name: "Ana", last_name: "Flores")
    assert voter.dob_ambiguous, "Parser confidence flag should still be updated on the record"
  ensure
    file&.close!
  end

  test "counts as updated when a field actually changes" do
    GecVoter.create!(
      first_name: "Juan",
      last_name: "Cruz",
      dob: Date.new(1985, 3, 15),
      village_name: "Barrigada",
      gec_list_date: Date.new(2026, 1, 25),
      imported_at: 1.month.ago
    )

    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Juan", "Cruz", Date.new(1985, 3, 15), "Barrigada", "VR-NEW" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "changes_only"
    ).call

    assert result.success
    assert_equal 1, result.stats[:updated], "VRN changed, should count as updated"
    assert_equal 0, result.stats[:matched_unchanged]
  end

  test "change_summary on gec_import returns correct data" do
    file = create_test_excel([
      [ "First Name", "Last Name", "Date of Birth", "Village", "Reg No" ],
      [ "Maria", "Santos", Date.new(1990, 6, 20), "Barrigada", "VR002" ]
    ])

    result = GecImportService.new(
      file_path: file.path,
      gec_list_date: Date.new(2026, 2, 25),
      import_type: "full_list"
    ).call

    summary = result.gec_import.change_summary
    assert_equal "full_list", summary[:import_type]
    assert_equal 1, summary[:total_records]
    assert_equal 1, summary[:new_records]
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

  def create_test_csv(rows)
    file = Tempfile.new([ "gec_test", ".csv" ])
    CSV.open(file.path, "w") do |csv|
      rows.each { |row| csv << row }
    end
    file
  end
end
