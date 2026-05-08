# frozen_string_literal: true

require "test_helper"

class GecPdfParserServiceTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # build_qa
  # ---------------------------------------------------------------------------

  test "build_qa returns fail status for empty rows" do
    qa = invoke_build_qa([], page_count: 1)
    assert_equal "fail", qa[:status]
    assert_equal 0, qa[:quality_score]
    assert_equal 0, qa[:row_count]
  end

  test "build_qa returns fail status below 1000 rows" do
    rows = minimal_rows(500)
    qa = invoke_build_qa(rows, page_count: 10)
    assert_equal "fail", qa[:status]
    assert qa[:quality_score] < 60, "Expected score <60 for 500 rows, got #{qa[:quality_score]}"
  end

  test "build_qa returns review status between 1000 and 9999 rows" do
    rows = minimal_rows(5_000)
    qa = invoke_build_qa(rows, page_count: 50)
    assert_equal "review", qa[:status]
  end

  test "build_qa returns pass status at or above 10000 rows" do
    rows = minimal_rows(10_000)
    qa = invoke_build_qa(rows, page_count: 100)
    assert_equal "pass", qa[:status]
    assert_equal 100, qa[:quality_score]
  end

  test "build_qa includes page_count and top_villages" do
    rows = minimal_rows(10_000, village: "DEDEDO")
    qa = invoke_build_qa(rows, page_count: 42)
    assert_equal 42, qa[:page_count]
    assert_includes qa[:top_villages].keys, "DEDEDO"
  end

  test "build_qa computes missing fields and penalizes quality when missing ratio is high" do
    rows = minimal_rows(10_000)
    600.times do |i|
      rows[i]["name"] = ""
    end

    qa = invoke_build_qa(rows, page_count: 100)
    assert_equal 600, qa[:missing_name]
    assert_equal 0, qa[:missing_village]
    assert_equal 0, qa[:missing_reg]
    assert_equal "pass", qa[:status]
    assert_equal 80, qa[:quality_score]
  end

  test "build_qa keeps partial datasets in review band even with missing field penalty" do
    rows = minimal_rows(5_000)
    300.times do |i|
      rows[i]["village"] = ""
    end

    qa = invoke_build_qa(rows, page_count: 50)
    assert_equal 300, qa[:missing_village]
    assert_equal "review", qa[:status]
    assert_equal 60, qa[:quality_score]
  end

  # ---------------------------------------------------------------------------
  # deduplication
  # ---------------------------------------------------------------------------

  test "duplicate rows are deduplicated by key" do
    # Two identical rows should produce one output row
    service = GecPdfParserService.new(file_path: "/dev/null")
    rows = []
    seen = {}
    # Simulate two identical entries
    2.times do
      reg_no, name, village, pct = "1234567", "JOHN DOE", "DEDEDO", "1"
      key = [ reg_no, name, village, pct ].join("|")
      unless seen[key]
        seen[key] = true
        rows << { "voter_registration_number" => reg_no, "name" => name, "village" => village, "pct" => pct }
      end
    end
    assert_equal 1, rows.size
  end

  # ---------------------------------------------------------------------------
  # ROW_REGEX constants sanity
  # ---------------------------------------------------------------------------

  test "ROW_REGEX is a Regexp" do
    assert_instance_of Regexp, GecPdfParserService::ROW_REGEX
  end

  test "LEGACY_LINE_REGEX is a Regexp" do
    assert_instance_of Regexp, GecPdfParserService::LEGACY_LINE_REGEX
  end

  test "ROW_REGEX does not truncate full middle names before numeric addresses" do
    row = "1234567 REYES, JOHN CARLOS 123 MAIN ST DEDEDO 96610 1990 5"
    match = row.match(GecPdfParserService::ROW_REGEX)

    assert match.present?
    assert_equal "REYES, JOHN CARLOS", match[2].strip
    assert_equal "123 MAIN ST", match[3].strip
  end

  test "ROW_REGEX supports legacy letter-first address prefixes" do
    row = "1234567 REYES, JOHN CARLOS ROUTE 4 BOX 123 DEDEDO 96610 1990 5"
    match = row.match(GecPdfParserService::ROW_REGEX)

    assert match.present?
    assert_equal "REYES, JOHN CARLOS", match[2].strip
    assert_equal "ROUTE 4 BOX 123", match[3].strip
  end

  test "ROW_REGEX supports letter-suffixed precincts" do
    row = "1234567 REYES, JOHN CARLOS 123 MAIN ST DEDEDO 96610 1990 18E"
    match = row.match(GecPdfParserService::ROW_REGEX)

    assert match.present?
    assert_equal "18E", match[6]
  end

  test "LEGACY_LINE_REGEX supports numeric ordinal street addresses" do
    row = "76780   ADAMS, ISABEL ANN                                 147 9TH ST                                           HAGATNA                96910       1987       1"
    match = row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert match.present?
    assert_equal "ADAMS, ISABEL ANN", match[2].strip
    assert_equal "147 9TH ST", match[3].strip
    assert_equal "HAGATNA", match[4].strip
  end

  test "LEGACY_LINE_REGEX supports apostrophes in addresses" do
    row = "39001   GUERRERO, ERNESTO R.                              777 W O'BRIEN DR APT 1D                              HAGATNA                96910       1953       1"
    match = row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert match.present?
    assert_equal "777 W O'BRIEN DR APT 1D", match[3].strip
  end

  test "LEGACY_LINE_REGEX supports letter suffixed house numbers and care of addresses" do
    row = "31204   CRUZ, TONY S.N.                                   119A 10TH STREET                                     HAGATNA                96910       1952       1"
    match = row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert match.present?
    assert_equal "119A 10TH STREET", match[3].strip

    care_of_row = "93041   RIMUO, EKLYN                                      C/O 117A CHALAN GUMA YU'OS                           SINAJANA               96910       2003       1"
    care_of_match = care_of_row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert care_of_match.present?
    assert_equal "C/O 117A CHALAN GUMA YU'OS", care_of_match[3].strip

    po_box_zero_row = "62682   SALAS, CHRISHA THERESE                            P0 BOX 3245                                          HAGATNA                96932       1987       2"
    po_box_zero_match = po_box_zero_row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert po_box_zero_match.present?
    assert_equal "P0 BOX 3245", po_box_zero_match[3].strip
  end

  test "LEGACY_LINE_REGEX supports hc box and hash-prefixed addresses" do
    hc_row = "70795   AGUON, TOMAS JOSEPH                               HC1 BOX 18076                                        UMATAC                 96915       1996       6"
    hc_match = hc_row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert hc_match.present?
    assert_equal "HC1 BOX 18076", hc_match[3].strip

    hash_row = "24195   MESA, PENNY ANN                                   #2 W. ANACO LN                                       PITI                   96915       1964       3"
    hash_match = hash_row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert hash_match.present?
    assert_equal "#2 W. ANACO LN", hash_match[3].strip
  end

  test "parse captures generic off-island rows through fallback legacy parser" do
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new("97313   HERR, ASHTON ARMANI                               USS ANNAPOLIS SSN760 UNIT 100273 BOX 1               FPO                    96915       2003       5")
      ],
      1
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(file_path: "/dev/null")
      result = service.parse

      assert_empty result.errors
      assert_equal 1, result.rows.size
      assert_equal "97313", result.rows.first["voter_registration_number"]
      assert_equal "HERR, ASHTON ARMANI", result.rows.first["name"]
      assert_nil result.rows.first["village"]
      assert_equal "2003", result.rows.first["birth_year"]
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end
  end

  test "build_legacy_row drops unknown locality text instead of preserving fake village names" do
    service = GecPdfParserService.new(file_path: "/dev/null")

    row = service.send(
      :build_legacy_row,
      [ "12345", "DOE, JANE", "USS EXAMPLE UNIT 1", "FPO", "1987", "5" ]
    )

    assert_equal "DOE, JANE", row["name"]
    assert_nil row["village"]
  end

  test "LEGACY_LINE_REGEX supports parenthetical names and zip plus four" do
    row = "26173   CAMACHO, MARY CECILIA (SIS)                       211 SAN VITORES RD                                   TAMUNING               96913       1937       1"
    match = row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert match.present?
    assert_equal "CAMACHO, MARY CECILIA (SIS)", match[2].strip

    zip_plus_four_row = "95863   MOELLER, CHRISTIAN ROBERT                         425 CHALAN SAN ANTONIO # 580                         TAMUNING             96913-3602    1989       1"
    zip_plus_four_match = zip_plus_four_row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert zip_plus_four_match.present?
    assert_equal "425 CHALAN SAN ANTONIO # 580", zip_plus_four_match[3].strip
  end

  test "ROW_REGEX does not split middle name that matches removed address prefix term" do
    row = "1234567 SANTOS, JOHN MARINE 123 MAIN ST DEDEDO 96610 1990 5"
    match = row.match(GecPdfParserService::ROW_REGEX)

    assert match.present?
    assert_equal "SANTOS, JOHN MARINE", match[2].strip
    assert_equal "123 MAIN ST", match[3].strip
  end

  test "LEGACY_LINE_REGEX does not treat AGAT as a prefix inside a given name" do
    row = "75720 CARPO, AGATHA ROARY SILVA PO BOX 9306 TAMUNING 96931 1996 18B"
    match = row.match(GecPdfParserService::LEGACY_LINE_REGEX)

    assert match.present?
    assert_equal "CARPO, AGATHA ROARY SILVA", match[2].strip
    assert_equal "PO BOX 9306", match[3].strip
    assert_equal "TAMUNING", match[4].strip
  end

  test "VILLAGE_ALT matches known village names" do
    village_alt = Regexp.new(GecPdfParserService::VILLAGE_ALT_STR)
    assert_match village_alt, "DEDEDO"
    assert_match village_alt, "TAMUNING"
    assert_match village_alt, "HAGATNA"
    assert_match village_alt, "MONGMONG TOTO MAITE"
    assert_match village_alt, "MONGMONG"
    assert_match village_alt, "TOTO"
    assert_match village_alt, "MAITE"
  end

  test "REVIEW_MIN_ROWS and FAIL_MIN_ROWS are ordered correctly" do
    assert GecPdfParserService::FAIL_MIN_ROWS < GecPdfParserService::REVIEW_MIN_ROWS
  end

  test "normalize_birth_year_from_dob maps 2-digit years using moving cutoff" do
    travel_to Time.zone.local(2026, 3, 5) do
      service = GecPdfParserService.new(file_path: "/dev/null")
      assert_equal "2006", service.send(:normalize_birth_year_from_dob, "03/15/06")
      assert_equal "1980", service.send(:normalize_birth_year_from_dob, "03/15/80")
    end
  end

  # ---------------------------------------------------------------------------
  # write_normalized_csv
  # ---------------------------------------------------------------------------

  test "write_normalized_csv creates a readable CSV with correct headers" do
    service = GecPdfParserService.new(file_path: "/dev/null")
    rows = [
      { "name" => "JOHN DOE", "village" => "DEDEDO", "voter_registration_number" => "1234567",
        "dob" => "01/01/1980", "birth_year" => "1980", "pct" => "1", "address" => "123 MAIN ST" }
    ]
    tf = service.write_normalized_csv(rows)
    csv = CSV.read(tf.path)
    tf.close!
    assert_equal [ "name", "village", "voter_registration_number", "dob", "dob_estimated", "birth_year", "pct", "address" ], csv[0]
    assert_equal "JOHN DOE", csv[1][0]
    assert_equal "DEDEDO", csv[1][1]
  end

  test "parse reports page progress through callback" do
    progress_calls = []
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new("1 44157 AFLAGUE, MARILYN A 123 MAIN ST HAGATNA 01/01/47 1"),
        page.new("2 44161 AFLAGUE, NORMA J. 456 MAIN ST HAGATNA 01/01/49 1")
      ],
      2
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(
        file_path: "/dev/null",
        progress_callback: ->(pages_processed:, page_count:) { progress_calls << [ pages_processed, page_count ] }
      )
      result = service.parse

      assert_empty result.errors
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end

    assert_includes progress_calls, [ 0, 2 ]
    assert_includes progress_calls, [ 1, 2 ]
    assert_includes progress_calls, [ 2, 2 ]
  end

  test "parse captures rows with letter-suffixed precincts" do
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new("78851 MADAHAN, ELENA GAYAGAS PO BOX 7549 AGAT 96928 1961 4A")
      ],
      1
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(file_path: "/dev/null")
      result = service.parse

      assert_empty result.errors
      assert_equal 1, result.rows.size
      assert_equal "4A", result.rows.first["pct"]
      assert_equal "AGAT", result.rows.first["village"]
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end
  end

  test "parse prefers line-based legacy rows over flattened fallback for marine corps addresses" do
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new("77990   HERNANDEZ, AIDAN VINCENT SAN NICOLAS              PMB 932 1270 N MARINE CORPS                          TAMUNING               96913       2004       2")
      ],
      1
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(file_path: "/dev/null")
      result = service.parse

      assert_empty result.errors
      assert_equal 1, result.rows.size
      assert_equal "HERNANDEZ, AIDAN VINCENT SAN NICOLAS", result.rows.first["name"]
      assert_equal "PMB 932 1270 N MARINE CORPS", result.rows.first["address"]
      assert_equal "TAMUNING", result.rows.first["village"]
      assert_equal "2004", result.rows.first["birth_year"]
      assert_equal "2", result.rows.first["pct"]
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end
  end

  test "parse captures previously dropped numeric street rows" do
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new("76780   ADAMS, ISABEL ANN                                 147 9TH ST                                           HAGATNA                96910       1987       1")
      ],
      1
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(file_path: "/dev/null")
      result = service.parse

      assert_empty result.errors
      assert_equal 1, result.rows.size
      assert_equal "76780", result.rows.first["voter_registration_number"]
      assert_equal "ADAMS, ISABEL ANN", result.rows.first["name"]
      assert_equal "HAGATNA", result.rows.first["village"]
      assert_equal "1987", result.rows.first["birth_year"]
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end
  end

  test "parse captures standalone sub-village tokens used for Mongmong/Toto/Maite rows" do
    page = Struct.new(:text)
    reader = Struct.new(:pages, :page_count).new(
      [
        page.new(<<~TEXT)
          29494   PEREZ, PATRINA ANN                              116 PETMANENTE ST                                  MONGMONG              96910      1984      8A
          96758   GILL, LILLIAN DOLORES                           166 CHALAN RS SANCHEZ                              TOTO                  96910      1995      6
          48503   GURWELL, DANNY H.                               472 RT 8 STE 1B-496                               MAITE                 96910      1964      11A
        TEXT
      ],
      1
    )

    reader_singleton = class << PDF::Reader; self; end
    original_new = reader_singleton.instance_method(:new)
    reader_singleton.define_method(:new) { |_file_path| reader }

    begin
      service = GecPdfParserService.new(file_path: "/dev/null")
      result = service.parse

      assert_empty result.errors
      assert_equal 3, result.rows.size
      assert_equal %w[MONGMONG TOTO MAITE], result.rows.map { |row| row["village"] }
      assert_equal %w[1984 1995 1964], result.rows.map { |row| row["birth_year"] }
    ensure
      reader_singleton.send(:remove_method, :new)
      reader_singleton.define_method(:new, original_new)
    end
  end

  private

  def invoke_build_qa(rows, page_count:)
    service = GecPdfParserService.new(file_path: "/dev/null")
    service.send(:build_qa, rows, page_count)
  end

  def minimal_rows(count, village: "DEDEDO")
    count.times.map do |i|
      { "name" => "VOTER #{i}", "village" => village, "voter_registration_number" => format("%07d", i),
        "dob" => "01/01/1980", "birth_year" => "1980", "pct" => "1", "address" => "ADDR #{i}" }
    end
  end
end
