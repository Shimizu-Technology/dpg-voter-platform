require "test_helper"

class NameParserTest < ActiveSupport::TestCase
  test "split_gec_name separates first middle and last names" do
    parsed = NameParser.split_gec_name("ADAMS, ISABEL ANN")

    assert_equal "ADAMS", parsed[:last_name]
    assert_equal "ISABEL", parsed[:first_name]
    assert_equal "ANN", parsed[:middle_name]
  end

  test "split_print_name handles first middle last format" do
    parsed = NameParser.split_print_name("Anna Maria Aguirre")

    assert_equal "Anna", parsed[:first_name]
    assert_equal "Maria", parsed[:middle_name]
    assert_equal "Aguirre", parsed[:last_name]
  end

  test "combine builds last comma first middle format" do
    combined = NameParser.combine(
      first_name: "Anna",
      middle_name: "Maria",
      last_name: "Aguirre",
      format: :last_comma_first
    )

    assert_equal "Aguirre, Anna Maria", combined
  end

  test "split_supporter_name preserves trailing parenthetical surname notes" do
    parsed = NameParser.split_supporter_name("Kaila Owen (Cruz)")

    assert_equal "Kaila", parsed[:first_name]
    assert_nil parsed[:middle_name]
    assert_equal "Owen (Cruz)", parsed[:last_name]
    assert_equal true, parsed[:uncertain]
  end

  test "split_supporter_name separates compact initials from surname" do
    parsed = NameParser.split_supporter_name("Christian J.C.Borja")

    assert_equal "Christian", parsed[:first_name]
    assert_equal "J.C.", parsed[:middle_name]
    assert_equal "Borja", parsed[:last_name]
    assert_equal true, parsed[:uncertain]
  end

  test "split_supporter_name keeps suffix with last name" do
    parsed = NameParser.split_supporter_name("John Burch II")

    assert_equal "John", parsed[:first_name]
    assert_nil parsed[:middle_name]
    assert_equal "Burch II", parsed[:last_name]
    assert_equal false, parsed[:uncertain]
  end
end
