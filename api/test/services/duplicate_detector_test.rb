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


  test "find_duplicates detects shared GEC voter link" do
    voter = GecVoter.create!(
      first_name: "Gec",
      last_name: "Duplicate",
      birth_year: 1980,
      address: "123 Test St",
      village: @village1,
      village_name: @village1.name,
      precinct_number: "1",
      voter_registration_number: "GEC-DUP-1",
      gec_list_date: Date.current,
      imported_at: Time.current
    )
    s1 = Supporter.create!(**@base_attrs, first_name: "Gec", last_name: "Duplicate", contact_number: "671-555-2001", village: @village1, verification_status: "verified")
    s2 = Supporter.create!(**@base_attrs, first_name: "Gec", last_name: "Duplicate", contact_number: "671-555-2002", village: @village2, verification_status: "verified")
    s1.update_columns(gec_voter_id: voter.id)
    s2.update_columns(gec_voter_id: voter.id)

    assert_includes DuplicateDetector.find_duplicates(s2.reload).pluck(:id), s1.id
  end

  test "find_duplicates detects same name and dob across villages" do
    dob = Date.new(1988, 8, 8)
    s1 = Supporter.create!(**@base_attrs, first_name: "Dob", last_name: "Duplicate", contact_number: "671-555-2101", village: @village1, dob: dob)
    s2 = Supporter.create!(**@base_attrs, first_name: "Dob", last_name: "Duplicate", contact_number: "671-555-2102", village: @village2, dob: dob)

    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "find_duplicates detects same name and normalized address" do
    s1 = Supporter.create!(**@base_attrs, first_name: "Address", last_name: "Duplicate", contact_number: "671-555-2201", village: @village1, street_address: "123 Chalan Example Road")
    s2 = Supporter.create!(**@base_attrs, first_name: "Address", last_name: "Duplicate", contact_number: "671-555-2202", village: @village1, street_address: "123 Chalan Example Rd")

    assert_includes DuplicateDetector.find_duplicates(s2).pluck(:id), s1.id
  end

  test "merge preserves DPG help and volunteer signals" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Help",
      last_name: "Merge",
      contact_number: "671-555-2301",
      village: @village1,
      review_status: "approved",
      contact_classification: "active_contact",
      support_status: "unknown",
      volunteer_status: "unknown"
    )
    duplicate = Supporter.create!(
      **@base_attrs,
      first_name: "Help",
      last_name: "Merge",
      contact_number: "671-555-2302",
      village: @village1,
      review_status: "pending",
      contact_classification: "new_intake",
      wants_to_volunteer: true,
      needs_voter_registration_help: true,
      needs_election_day_ride: true,
      support_status: "supporter",
      volunteer_status: "interested"
    )

    DuplicateDetector.resolve!(duplicate, action: "merge", merge_into: approved)

    approved.reload
    assert_equal true, approved.wants_to_volunteer
    assert_equal true, approved.needs_voter_registration_help
    assert_equal true, approved.needs_election_day_ride
    assert_equal "supporter", approved.support_status
    assert_equal "interested", approved.volunteer_status
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

  test "dismiss persists ignored pair so scans do not reflag it" do
    original = Supporter.create!(**@base_attrs, first_name: "Ignored", last_name: "Pair", contact_number: "671-777-0003", village: @village1)
    newer = Supporter.create!(**@base_attrs, first_name: "Ignored", last_name: "Pair", contact_number: "671-777-0004", village: @village1)

    original.reload
    newer.reload
    assert original.potential_duplicate?
    assert newer.potential_duplicate?

    assert_difference -> { DuplicatePairDismissal.count }, 1 do
      DuplicateDetector.resolve!(newer, action: "dismiss")
    end

    assert_empty DuplicateDetector.find_duplicates(newer.reload).pluck(:id)

    DuplicateDetector.scan_all!

    assert_equal false, original.reload.potential_duplicate?
    assert_equal false, newer.reload.potential_duplicate?
  end

  test "review_group_count counts duplicate review pairs instead of flagged records" do
    original = Supporter.create!(**@base_attrs, first_name: "Group", last_name: "Count", contact_number: "671-777-0005", village: @village1)
    newer = Supporter.create!(**@base_attrs, first_name: "Group", last_name: "Count", contact_number: "671-777-0006", village: @village1)

    original.reload
    newer.reload
    assert original.potential_duplicate?
    assert newer.potential_duplicate?
    assert_equal 2, Supporter.where(id: [ original.id, newer.id ]).potential_duplicates_only.count
    assert_equal 1, DuplicateDetector.review_group_count(Supporter.where(id: [ original.id, newer.id ]).potential_duplicates_only)
  end

  test "dismiss reconciles reverse-pointing records without clearing unrelated warnings" do
    a = Supporter.create!(**@base_attrs, first_name: "ChainA", last_name: "Dismiss", contact_number: "671-777-0111", village: @village1)
    b = Supporter.create!(**@base_attrs, first_name: "ChainB", last_name: "Dismiss", contact_number: "671-777-0111", village: @village1)
    c = Supporter.create!(**@base_attrs, first_name: "ChainC", last_name: "Dismiss", contact_number: "671-777-0111", village: @village1)
    DuplicateDetector.scan_all!

    a.reload
    b.reload
    c.reload
    assert a.potential_duplicate?
    assert b.potential_duplicate?
    assert c.potential_duplicate?
    assert_equal a.id, c.duplicate_of_id

    DuplicateDetector.resolve!(a, action: "dismiss", dismissed_match: b)

    a.reload
    b.reload
    c.reload
    assert DuplicatePairDismissal.dismissed?(a.id, b.id)
    assert a.potential_duplicate?, "Dismissed record should stay flagged because it still matches a third unresolved record"
    assert b.potential_duplicate?, "Matched record should stay flagged because it still matches a third unresolved record"
    assert c.potential_duplicate?, "Reverse-pointing record should be reconciled, not silently cleared"
    assert_includes DuplicateDetector.find_duplicates(c).pluck(:id), a.id
  end

  test "dismiss clears both sides of a duplicate warning" do
    original = Supporter.create!(**@base_attrs, first_name: "Not", last_name: "Duplicate", contact_number: "671-777-0101", village: @village1)
    newer = Supporter.create!(**@base_attrs, first_name: "Not", last_name: "Duplicate", contact_number: "671-777-0102", village: @village1)

    original.reload
    newer.reload
    assert original.potential_duplicate?
    assert newer.potential_duplicate?

    DuplicateDetector.resolve!(newer, action: "dismiss")

    original.reload
    newer.reload
    assert_equal false, original.potential_duplicate?
    assert_equal false, newer.potential_duplicate?
    assert_nil original.duplicate_of_id
    assert_nil newer.duplicate_of_id
    assert_nil original.duplicate_notes
    assert_nil newer.duplicate_notes
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

  test "merge preserves explicit false registered voter value" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Registered",
      last_name: "False",
      contact_number: "671-777-1003",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      registered_voter: false
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Registered",
      last_name: "False",
      contact_number: "671-777-1003",
      village: @village1,
      review_status: "pending",
      public_review_status: "approved",
      registered_voter: true
    )

    DuplicateDetector.resolve!(public_signup, action: "merge", merge_into: approved)

    assert_equal false, approved.reload.registered_voter
  end

  test "merge copies registered voter when kept record is unknown" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Registered",
      last_name: "Unknown",
      contact_number: "671-777-1004",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      registered_voter: nil
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Registered",
      last_name: "Unknown",
      contact_number: "671-777-1004",
      village: @village1,
      review_status: "pending",
      public_review_status: "approved",
      registered_voter: true
    )

    DuplicateDetector.resolve!(public_signup, action: "merge", merge_into: approved)

    assert_equal true, approved.reload.registered_voter
  end

  test "merge preserves explicit no registered voter status" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Registration",
      last_name: "No",
      contact_number: "671-777-1005",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      registered_voter_status: "no"
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Registration",
      last_name: "No",
      contact_number: "671-777-1005",
      village: @village1,
      review_status: "pending",
      public_review_status: "approved",
      registered_voter_status: "yes"
    )

    DuplicateDetector.resolve!(public_signup, action: "merge", merge_into: approved)

    assert_equal "no", approved.reload.registered_voter_status
  end

  test "merge copies registered voter status when kept record is not sure" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Registration",
      last_name: "Unknown",
      contact_number: "671-777-1006",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      registered_voter_status: "not_sure"
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Registration",
      last_name: "Unknown",
      contact_number: "671-777-1006",
      village: @village1,
      review_status: "pending",
      public_review_status: "approved",
      registered_voter_status: "yes"
    )

    DuplicateDetector.resolve!(public_signup, action: "merge", merge_into: approved)

    assert_equal "yes", approved.reload.registered_voter_status
  end

  test "merge preserves explicit false self-reported voter signal" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Self",
      last_name: "Reported",
      contact_number: "671-777-1002",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable"
    )
    approved.update_columns(
      self_reported_registered_voter: false,
      registered_voter: nil,
      registered_voter_status: "not_sure"
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

    approved.reload
    assert_equal false, approved.self_reported_registered_voter
    assert_equal "not_sure", approved.registered_voter_status
  end

  test "merge preserves affirmative self-reported voter signal when kept record is unknown" do
    approved = Supporter.create!(
      **@base_attrs,
      first_name: "Self",
      last_name: "Reported Unknown",
      contact_number: "671-777-1007",
      village: @village1,
      review_status: "approved",
      public_review_status: "not_applicable",
      self_reported_registered_voter: nil
    )
    public_signup = Supporter.create!(
      **@base_attrs,
      first_name: "Self",
      last_name: "Reported Unknown",
      contact_number: "671-777-1007",
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
