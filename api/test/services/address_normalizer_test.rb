require "test_helper"

class AddressNormalizerTest < ActiveSupport::TestCase
  test "canonical address normalizes common street suffixes" do
    assert_equal "221 lirio ave", AddressNormalizer.canonical_address("221 Lirio Avenue")
    assert_equal "221 lirio ave", AddressNormalizer.canonical_address("221 Lirio Ave.")
  end

  test "canonical address removes trailing village and locality text" do
    assert_equal "221 lirio ave", AddressNormalizer.canonical_address("221 Lirio Avenue Barrigada Heights", village_name: "Barrigada")
    assert_equal "221 lirio ave", AddressNormalizer.canonical_address("221 Lirio Ave Barrigada", village_name: "Barrigada")
  end

  test "canonical key keeps villages separate" do
    assert_not_equal(
      AddressNormalizer.canonical_key("221 Lirio Ave", village_name: "Barrigada"),
      AddressNormalizer.canonical_key("221 Lirio Ave", village_name: "Dededo")
    )
  end

  test "canonical address normalizes po box variants" do
    assert_equal "po box 761", AddressNormalizer.canonical_address("P.O. Box 761")
    assert_equal "po box 761", AddressNormalizer.canonical_address("Post Office Box 761")
  end
end
