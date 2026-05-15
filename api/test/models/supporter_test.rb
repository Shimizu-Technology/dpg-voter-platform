require "test_helper"

class SupporterTest < ActiveSupport::TestCase
  def setup
    @village_one = Village.create!(name: "Test Village One")
    @village_two = Village.create!(name: "Test Village Two")

    @precinct_one = Precinct.create!(number: "1", village: @village_one)
    @precinct_two = Precinct.create!(number: "2", village: @village_two)

    @block_one = Block.create!(name: "Block One", village: @village_one)
    @block_two = Block.create!(name: "Block Two", village: @village_two)
  end

  test "is valid when precinct and village match" do
    supporter = Supporter.new(
      first_name: "Valid", last_name: "Supporter", print_name: "Valid Supporter",
      contact_number: "6715551000",
      village: @village_one,
      precinct: @precinct_one,
      source: "staff_entry",
      status: "active"
    )

    assert supporter.valid?
  end

  test "is invalid when precinct belongs to different village" do
    supporter = Supporter.new(
      first_name: "Invalid", last_name: "Precinct Supporter", print_name: "Invalid Precinct Supporter",
      contact_number: "6715551001",
      village: @village_one,
      precinct: @precinct_two,
      source: "staff_entry",
      status: "active"
    )

    assert_not supporter.valid?
    assert_includes supporter.errors[:precinct_id], "must belong to the selected village"
  end

  test "is invalid when block belongs to different village" do
    supporter = Supporter.new(
      first_name: "Invalid", last_name: "Block Supporter", print_name: "Invalid Block Supporter",
      contact_number: "6715551002",
      village: @village_one,
      block: @block_two,
      source: "staff_entry",
      status: "active"
    )

    assert_not supporter.valid?
    assert_includes supporter.errors[:block_id], "must belong to the selected village"
  end

  test "is valid when block and village match" do
    supporter = Supporter.new(
      first_name: "Valid", last_name: "Block Supporter", print_name: "Valid Block Supporter",
      contact_number: "6715551003",
      village: @village_one,
      block: @block_one,
      source: "staff_entry",
      status: "active"
    )

    assert supporter.valid?
  end

  test "allows blank phone for staff/manual attribution" do
    supporter = Supporter.new(
      first_name: "NoPhone",
      last_name: "Manual",
      village: @village_one,
      source: "staff_entry",
      attribution_method: "staff_manual",
      turnout_status: "unknown",
      verification_status: "unverified",
      status: "active"
    )

    assert supporter.valid?
  end

  test "requires phone for public signup attribution" do
    supporter = Supporter.new(
      first_name: "NoPhone",
      last_name: "Public",
      village: @village_one,
      source: "qr_signup",
      attribution_method: "public_signup",
      turnout_status: "unknown",
      verification_status: "unverified",
      status: "active"
    )

    assert_not supporter.valid?
    assert_includes supporter.errors[:contact_number], "can't be blank"
  end

  test "auto-assigns a new precinct when village changes and precinct is cleared" do
    single_precinct_village = Village.create!(name: "Single Precinct Village")
    single_precinct = Precinct.create!(number: "SP-1", village: single_precinct_village)

    supporter = Supporter.create!(
      first_name: "Moved",
      last_name: "Supporter",
      contact_number: "6715551004",
      village: @village_one,
      precinct: @precinct_one,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      turnout_status: "unknown"
    )

    supporter.update!(village: single_precinct_village, precinct: nil)

    assert_equal single_precinct.id, supporter.reload.precinct_id
  end

  test "keeps an explicitly selected precinct on update" do
    precinct_b = Precinct.create!(number: "1B", village: @village_one)
    supporter = Supporter.create!(
      first_name: "Manual",
      last_name: "Override",
      contact_number: "6715551005",
      village: @village_one,
      precinct: @precinct_one,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      turnout_status: "unknown"
    )

    supporter.update!(precinct: precinct_b)

    assert_equal precinct_b.id, supporter.reload.precinct_id
  end

  test "does not auto-assign precinct when only last name changes on an existing unassigned supporter" do
    no_precinct_village = Village.create!(name: "No Precinct Village")
    supporter = Supporter.create!(
      first_name: "No",
      last_name: "Precinct",
      contact_number: "6715551006",
      village: no_precinct_village,
      precinct: nil,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      turnout_status: "unknown"
    )
    # Move the existing unassigned supporter into the target village without
    # invoking the callback path this test is intentionally exercising.
    supporter.update_columns(village_id: @village_one.id, precinct_id: nil)

    supporter.update!(last_name: "Corrected")

    assert_nil supporter.reload.precinct_id
  end

  test "official supporters preserves legacy supporter member and volunteer count semantics" do
    supporter = Supporter.create!(
      first_name: "Known",
      last_name: "Supporter",
      contact_number: "6715552001",
      village: @village_one,
      source: "staff_entry",
      contact_classification: "active_contact",
      support_status: "supporter",
      status: "active"
    )
    member = Supporter.create!(
      first_name: "Known",
      last_name: "Member",
      contact_number: "6715552002",
      village: @village_one,
      source: "staff_entry",
      contact_classification: "active_contact",
      membership_status: "member",
      status: "active"
    )
    volunteer = Supporter.create!(
      first_name: "Known",
      last_name: "Volunteer",
      contact_number: "6715552003",
      village: @village_one,
      source: "staff_entry",
      contact_classification: "active_contact",
      volunteer_status: "interested",
      status: "active"
    )
    undecided = Supporter.create!(
      first_name: "Still",
      last_name: "Undecided",
      contact_number: "6715552004",
      village: @village_one,
      source: "staff_entry",
      contact_classification: "active_contact",
      support_status: "undecided",
      status: "active"
    )
    pending_intake = Supporter.create!(
      first_name: "Pending",
      last_name: "Relationship",
      contact_number: "6715552005",
      village: @village_one,
      source: "staff_entry",
      contact_classification: "new_intake",
      support_status: "supporter",
      membership_status: "member",
      volunteer_status: "interested",
      review_status: "pending",
      status: "active"
    )

    official_ids = Supporter.official_supporters.pluck(:id)

    assert_includes official_ids, supporter.id
    assert_includes official_ids, member.id
    assert_includes official_ids, volunteer.id
    refute_includes official_ids, undecided.id
    refute_includes official_ids, pending_intake.id
    refute_includes Supporter.classified_supporters.pluck(:id), pending_intake.id
    refute_includes Supporter.members.pluck(:id), pending_intake.id
    refute_includes Supporter.volunteers.pluck(:id), pending_intake.id
  end

  test "household_members excludes self from preloaded household supporters" do
    household_group = HouseholdGroup.create!(village: @village_one)
    primary = Supporter.create!(
      first_name: "Primary",
      last_name: "Household",
      contact_number: "6715551007",
      village: @village_one,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      turnout_status: "unknown",
      household_group: household_group,
      household_primary: true
    )
    member = Supporter.create!(
      first_name: "Second",
      last_name: "Household",
      contact_number: "6715551008",
      village: @village_one,
      source: "staff_entry",
      status: "active",
      verification_status: "unverified",
      turnout_status: "unknown",
      household_group: household_group,
      household_primary: false
    )

    loaded_primary = Supporter.includes(household_group: :supporters).find(primary.id)

    assert_kind_of Array, loaded_primary.household_members
    assert_equal [ member.id ], loaded_primary.household_members.map(&:id)
  end
end
