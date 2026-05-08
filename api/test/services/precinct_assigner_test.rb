# frozen_string_literal: true

require "test_helper"

class PrecinctAssignerTest < ActiveSupport::TestCase
  setup do
    @campaign = Campaign.find_or_create_by!(name: "Test Campaign") do |c|
      c.election_year = 2026
      c.election_type = "primary"
      c.status = "active"
      c.candidate_names = "Test"
      c.party = "Test"
    end

    # Single-precinct village
    @hagatna = Village.create!(name: "Test Hagåtña")
    @hagatna_p1 = Precinct.create!(village: @hagatna, number: "1", alpha_range: "A-Z", registered_voters: 344)

    # Two-precinct village (simple split)
    @hagat = Village.create!(name: "Test Hågat")
    @hagat_p4  = Precinct.create!(village: @hagat, number: "4",  alpha_range: "A-L",  registered_voters: 1027)
    @hagat_p4a = Precinct.create!(village: @hagat, number: "4A", alpha_range: "M-Z",  registered_voters: 918)

    # Three-precinct village (two-char boundaries)
    @yona = Village.create!(name: "Test Yona")
    @yona_p10  = Precinct.create!(village: @yona, number: "10",  alpha_range: "A-D",  registered_voters: 967)
    @yona_p10a = Precinct.create!(village: @yona, number: "10A", alpha_range: "E-Pd", registered_voters: 905)
    @yona_p10b = Precinct.create!(village: @yona, number: "10B", alpha_range: "Pe-Z", registered_voters: 947)

    # Two-char boundary village
    @inalahan = Village.create!(name: "Test Inalåhan")
    @inalahan_p8  = Precinct.create!(village: @inalahan, number: "8",  alpha_range: "A-Md", registered_voters: 731)
    @inalahan_p8a = Precinct.create!(village: @inalahan, number: "8A", alpha_range: "Me-Z", registered_voters: 658)
  end

  # --- Single precinct village ---

  test "assigns only precinct when village has one" do
    supporter = build_supporter(village: @hagatna, last_name: "Cruz")
    assert_equal @hagatna_p1, PrecinctAssigner.assign(supporter)
  end

  test "assigns only precinct even with nil last_name for single-precinct village" do
    supporter = build_supporter(village: @hagatna, last_name: nil)
    assert_equal @hagatna_p1, PrecinctAssigner.assign(supporter)
  end

  # --- Simple two-way split (A-L / M-Z) ---

  test "assigns A-L precinct for name starting with A" do
    supporter = build_supporter(village: @hagat, last_name: "Adams")
    assert_equal @hagat_p4, PrecinctAssigner.assign(supporter)
  end

  test "assigns A-L precinct for name starting with L" do
    supporter = build_supporter(village: @hagat, last_name: "Lopez")
    assert_equal @hagat_p4, PrecinctAssigner.assign(supporter)
  end

  test "assigns M-Z precinct for name starting with M" do
    supporter = build_supporter(village: @hagat, last_name: "Martinez")
    assert_equal @hagat_p4a, PrecinctAssigner.assign(supporter)
  end

  test "assigns M-Z precinct for name starting with Z" do
    supporter = build_supporter(village: @hagat, last_name: "Zamora")
    assert_equal @hagat_p4a, PrecinctAssigner.assign(supporter)
  end

  # --- Three-way split with two-char boundaries (A-D / E-Pd / Pe-Z) ---

  test "assigns A-D precinct for name starting with C" do
    supporter = build_supporter(village: @yona, last_name: "Cruz")
    assert_equal @yona_p10, PrecinctAssigner.assign(supporter)
  end

  test "assigns A-D precinct for name starting with D" do
    supporter = build_supporter(village: @yona, last_name: "Duenas")
    assert_equal @yona_p10, PrecinctAssigner.assign(supporter)
  end

  test "assigns E-Pd precinct for name starting with E" do
    supporter = build_supporter(village: @yona, last_name: "Edwards")
    assert_equal @yona_p10a, PrecinctAssigner.assign(supporter)
  end

  test "assigns E-Pd precinct for name starting with Pa" do
    supporter = build_supporter(village: @yona, last_name: "Pangelinan")
    assert_equal @yona_p10a, PrecinctAssigner.assign(supporter)
  end

  test "assigns E-Pd precinct for name starting with Pd" do
    supporter = build_supporter(village: @yona, last_name: "Pdtest")
    assert_equal @yona_p10a, PrecinctAssigner.assign(supporter)
  end

  test "assigns Pe-Z precinct for name starting with Pe" do
    supporter = build_supporter(village: @yona, last_name: "Peterson")
    assert_equal @yona_p10b, PrecinctAssigner.assign(supporter)
  end

  test "assigns Pe-Z precinct for name starting with S" do
    supporter = build_supporter(village: @yona, last_name: "Santos")
    assert_equal @yona_p10b, PrecinctAssigner.assign(supporter)
  end

  test "assigns Pe-Z precinct for name starting with Z" do
    supporter = build_supporter(village: @yona, last_name: "Zaragoza")
    assert_equal @yona_p10b, PrecinctAssigner.assign(supporter)
  end

  # --- Two-char boundary (A-Md / Me-Z) ---

  test "assigns A-Md precinct for name starting with Ma" do
    supporter = build_supporter(village: @inalahan, last_name: "Martinez")
    assert_equal @inalahan_p8, PrecinctAssigner.assign(supporter)
  end

  test "assigns A-Md precinct for name starting with Mc" do
    supporter = build_supporter(village: @inalahan, last_name: "McDonald")
    assert_equal @inalahan_p8, PrecinctAssigner.assign(supporter)
  end

  test "assigns A-Md precinct for name starting with Md" do
    supporter = build_supporter(village: @inalahan, last_name: "Mdtest")
    assert_equal @inalahan_p8, PrecinctAssigner.assign(supporter)
  end

  test "assigns Me-Z precinct for name starting with Me" do
    supporter = build_supporter(village: @inalahan, last_name: "Medina")
    assert_equal @inalahan_p8a, PrecinctAssigner.assign(supporter)
  end

  test "assigns Me-Z precinct for name starting with N" do
    supporter = build_supporter(village: @inalahan, last_name: "Nelson")
    assert_equal @inalahan_p8a, PrecinctAssigner.assign(supporter)
  end

  # --- Edge cases ---

  test "returns nil when village_id is blank" do
    supporter = Supporter.new(last_name: "Cruz", first_name: "Test", contact_number: "671-555-0001")
    assert_nil PrecinctAssigner.assign(supporter)
  end

  test "returns nil when last_name is blank for multi-precinct village" do
    supporter = build_supporter(village: @hagat, last_name: nil)
    assert_nil PrecinctAssigner.assign(supporter)
  end

  test "returns nil when last_name is empty string for multi-precinct village" do
    supporter = build_supporter(village: @hagat, last_name: "")
    assert_nil PrecinctAssigner.assign(supporter)
  end

  test "assign_id returns the precinct id" do
    supporter = build_supporter(village: @hagatna, last_name: "Cruz")
    assert_equal @hagatna_p1.id, PrecinctAssigner.assign_id(supporter)
  end

  test "handles case-insensitive last names" do
    supporter = build_supporter(village: @hagat, last_name: "ADAMS")
    assert_equal @hagat_p4, PrecinctAssigner.assign(supporter)
  end

  test "handles whitespace in last names" do
    supporter = build_supporter(village: @hagat, last_name: "  Adams  ")
    assert_equal @hagat_p4, PrecinctAssigner.assign(supporter)
  end

  private

  def build_supporter(village:, last_name:)
    Supporter.new(
      village: village,
      first_name: "Test",
      last_name: last_name,
      contact_number: "671-555-#{rand(1000..9999)}"
    )
  end
end
