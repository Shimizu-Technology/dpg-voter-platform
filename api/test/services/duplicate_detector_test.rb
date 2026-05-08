require "test_helper"

class DuplicateDetectorTest < ActiveSupport::TestCase
  setup do
    @village1 = Village.first || Village.create!(name: "Test Village", region: "Central")
    @village2 = Village.second || Village.create!(name: "Test Village 2", region: "South")
    @base_attrs = { status: "active", verification_status: "unverified" }
  end

  test "find_duplicates detects normalized phone matches" do
    s1 = Supporter.create!(**@base_attrs, first_name: "A", last_name: "B", contact_number: "671-555-1234", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "C", last_name: "D", contact_number: "+16715551234", village: @village2)

    assert_equal s1.normalized_phone, s2.normalized_phone
    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
    assert_includes DuplicateDetector.find_duplicates(s1).pluck(:id), s2.id
  end

  test "find_duplicates detects case-insensitive email matches" do
    s1 = Supporter.create!(**@base_attrs, first_name: "E", last_name: "F", contact_number: "671-111-0001", village: @village1, email: "test@example.com")
    s2 = Supporter.create!(**@base_attrs, first_name: "G", last_name: "H", contact_number: "671-111-0002", village: @village2, email: "TEST@Example.COM")

    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "find_duplicates detects name+village matches" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-222-0001", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-222-0002", village: @village1)

    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "find_duplicates does not match different villages for name" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-333-0001", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-333-0002", village: @village2)

    assert_not_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "scan_all! finds duplicates in bulk using SQL" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Scan", last_name: "Test1", contact_number: "671-444-0001", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "Scan", last_name: "Test2", contact_number: "+16714440001", village: @village2)

    # Reset flags so scan_all! can find them fresh
    Supporter.where(id: [ s1.id, s2.id ]).update_all(potential_duplicate: false, duplicate_of_id: nil, duplicate_notes: nil)

    count = DuplicateDetector.scan_all!
    assert count > 0

    s2.reload
    assert s2.potential_duplicate?
    assert_equal s1.id, s2.duplicate_of_id
  end

  test "normalized_phone is set before save" do
    s = Supporter.create!(**@base_attrs, first_name: "Norm", last_name: "Phone", contact_number: "+1-671-555-9876", village: @village1)
    assert_equal "6715559876", s.normalized_phone
  end

  test "find_duplicates detects swapped name matches" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Cruz", last_name: "Maria", contact_number: "671-555-0001", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-555-0002", village: @village1)

    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "bidirectional flagging works for both supporters" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Bi", last_name: "Dir1", contact_number: "671-666-0001", village: @village1)
    s2 = Supporter.create!(**@base_attrs, first_name: "Bi", last_name: "Dir2", contact_number: "+16716660001", village: @village2)

    # after_create triggers flag_if_duplicate!, so both should be flagged
    s1.reload
    s2.reload
    assert s2.potential_duplicate?, "Newer duplicate should be flagged"
    assert s1.potential_duplicate?, "Original should also be flagged"
  end

  test "merge clears stale duplicate flag from kept record when no active duplicates remain" do
    original = Supporter.create!(**@base_attrs, first_name: "Talia", last_name: "Example", contact_number: "671-777-0001", village: @village1)
    newer = Supporter.create!(**@base_attrs, first_name: "Talia", last_name: "Example", contact_number: "671-777-0002", village: @village1)

    original.reload
    newer.reload
    assert original.potential_duplicate?
    assert newer.potential_duplicate?

    DuplicateDetector.resolve!(original, action: "merge", merge_into: newer)

    original.reload
    newer.reload

    assert_equal "duplicate", original.status
    assert_equal false, original.potential_duplicate?
    assert_equal newer.id, original.duplicate_of_id
    assert_equal false, newer.potential_duplicate?
    assert_nil newer.duplicate_of_id
    assert_nil newer.duplicate_notes
    assert_not_nil newer.duplicate_checked_at
  end

  test "merge copies email into kept record when existing email is blank string" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Email",
      last_name: "Merge",
      contact_number: "671-777-1001",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      email: ""
    )
    pending = Supporter.create!(
      **@base_attrs,
      first_name: "Email",
      last_name: "Merge",
      contact_number: "671-777-1001",
      village: @village1,
      review_status: "pending",
      public_review_status: "not_applicable",
      email: "email.merge@example.com"
    )

    DuplicateDetector.resolve!(pending, action: "merge", merge_into: approved)

    assert_equal "email.merge@example.com", approved.reload.email
  end

  test "merge preserves affirmative self-reported voter signal" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Self",
      last_name: "Reported",
      contact_number: "671-777-1002",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      self_reported_registered_voter: false
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Self",
      last_name: "Reported",
      contact_number: "671-777-1002",
      village: @village1,
      review_status: "pending",
      public_review_status: "approved",
      self_reported_registered_voter: true
    )

    DuplicateDetector.resolve!(public_signup, action: "merge", merge_into: approved)

    assert_equal true, approved.reload.self_reported_registered_voter
  end

  test "find_duplicates ignores supporters already marked duplicate" do
    original = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-888-0001", village: @village1)
    merged = Supporter.create!(**@base_attrs, first_name: "Maria", last_name: "Cruz", contact_number: "671-888-0002", village: @village1)

    merged.update!(status: "duplicate", potential_duplicate: false, duplicate_of_id: original.id)

    assert_empty DuplicateDetector.find_duplicates(original).to_a
  end

  test "find_duplicates ignores supporters rejected from review workflow" do
    remaining = Supporter.create!(**@base_attrs, first_name: "Reject", last_name: "Candidate", contact_number: "671-999-0001", village: @village1)
    rejected = Supporter.create!(**@base_attrs, first_name: "Reject", last_name: "Candidate", contact_number: "671-999-0002", village: @village1)

    rejected.update!(review_status: "rejected")

    assert_empty DuplicateDetector.find_duplicates(remaining).to_a
    duplicate_ids = Supporter.potential_duplicates(
      remaining.print_name,
      remaining.village_id,
      first_name: remaining.first_name,
      last_name: remaining.last_name
    ).pluck(:id)
    assert_includes duplicate_ids, remaining.id
    assert_not_includes duplicate_ids, rejected.id
  end

  test "scan_all clears stale duplicate flags left behind by rejected records" do
    remaining = Supporter.create!(**@base_attrs, first_name: "Stale", last_name: "Flag", contact_number: "671-999-1001", village: @village1)
    rejected = Supporter.create!(**@base_attrs, first_name: "Stale", last_name: "Flag", contact_number: "671-999-1002", village: @village1)

    remaining.reload
    rejected.reload
    assert remaining.potential_duplicate?
    assert rejected.potential_duplicate?

    rejected.update!(review_status: "rejected")
    DuplicateDetector.scan_all!

    assert_equal false, remaining.reload.potential_duplicate
    assert_equal false, rejected.reload.potential_duplicate
  end

  test "normalized_phone handles empty and nil gracefully" do
    assert_nil Supporter.normalize_phone(nil)
    assert_nil Supporter.normalize_phone("")
    assert_equal "6715551234", Supporter.normalize_phone("671-555-1234")
    assert_equal "6715551234", Supporter.normalize_phone("+16715551234")
    assert_equal "6715551234", Supporter.normalize_phone("1-671-555-1234")
  end
end
