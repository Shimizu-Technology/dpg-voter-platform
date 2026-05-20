# frozen_string_literal: true

class DuplicateDetector
  # Finds potential duplicates for a given supporter using indexed SQL queries.
  # Checks: normalized phone match, exact email match, name + village match.
  # Returns an ActiveRecord relation of matching supporters (excludes self).
  def self.find_duplicates(supporter)
    return Supporter.none if supporter.nil?

    match_ids = Set.new
    active_scope = Supporter.duplicate_review_candidates.where.not(id: supporter.id)

    # 1. Normalized phone match (uses index on normalized_phone)
    if supporter.normalized_phone.present?
      active_scope.where(normalized_phone: supporter.normalized_phone)
                  .pluck(:id)
                  .each { |id| match_ids << id }
    end

    # 2. Case-insensitive email match (uses index on email)
    if supporter.email.present?
      active_scope.where("LOWER(email) = LOWER(?)", supporter.email.strip)
                  .pluck(:id)
                  .each { |id| match_ids << id }
    end

    # 3. Same confirmed GEC voter link. This is the strongest signal because
    # staff may create a contact from the voter list and the same person may
    # later sign up publicly or through a QR code.
    if supporter.gec_voter_id.present?
      active_scope.where(gec_voter_id: supporter.gec_voter_id)
                  .pluck(:id)
                  .each { |id| match_ids << id }
    end

    # 4. Name-based matches. Name + village is intentionally broad for intake
    # cleanup, while name + DOB or name + normalized address can catch cases
    # where the person signs up under a different village from the GEC/contact
    # record but is still likely the same person.
    if supporter.first_name.present? && supporter.last_name.present?
      fn = supporter.first_name.downcase.strip
      ln = supporter.last_name.downcase.strip

      # Exact name match in same village
      if supporter.village_id.present?
        active_scope.where(village_id: supporter.village_id)
                    .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?", fn, ln)
                    .pluck(:id)
                    .each { |id| match_ids << id }

        # Swapped name match (First <-> Last) in same village
        active_scope.where(village_id: supporter.village_id)
                    .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?", ln, fn)
                    .pluck(:id)
                    .each { |id| match_ids << id }
      end

      if supporter.dob.present?
        active_scope.where(dob: supporter.dob)
                    .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?", fn, ln)
                    .pluck(:id)
                    .each { |id| match_ids << id }
      end

      address_duplicate_ids(supporter, active_scope: active_scope, first_name: fn, last_name: ln)
        .each { |id| match_ids << id }
    end

    filtered_match_ids = match_ids.to_a - DuplicatePairDismissal.match_ids_for(supporter.id, match_ids.to_a)
    Supporter.duplicate_review_candidates.where(id: filtered_match_ids)
  end

  def self.review_group_count(scope = Supporter.potential_duplicates_only.active)
    keys = Set.new

    scope.pluck(:id, :duplicate_of_id).each do |id, duplicate_of_id|
      key = if duplicate_of_id.present?
        [ id, duplicate_of_id ].minmax.join("-")
      else
        "solo-#{id}"
      end
      keys << key
    end

    keys.size
  end

  # Flag a supporter as potential duplicate and record which supporter it matches.
  def self.flag_if_duplicate!(supporter)
    duplicates = find_duplicates(supporter)
    return if duplicates.empty?

    original = duplicates.order(:created_at).first

    supporter.update_columns(
      potential_duplicate: true,
      duplicate_of_id: original.id,
      duplicate_notes: build_notes(supporter, duplicates)
    )

    unless original.potential_duplicate?
      original.update_columns(
        potential_duplicate: true,
        duplicate_of_id: supporter.id,
        duplicate_notes: "Has #{duplicates.count} potential duplicate(s) — newest: ##{supporter.id}"
      )
    end
  end

  # Resolve a duplicate: mark as reviewed, optionally merge into another record.
  def self.resolve!(supporter, action:, merge_into: nil, dismissed_match: nil, resolved_by: nil)
    case action
    when "dismiss"
      dismiss_duplicate_pair!(supporter, dismissed_match: dismissed_match, resolved_by: resolved_by)
    when "merge"
      raise ArgumentError, "merge_into required for merge action" unless merge_into

      impacted_active_ids = Supporter.active
                                    .where("id = ? OR duplicate_of_id IN (?, ?)", merge_into.id, supporter.id, merge_into.id)
                                    .pluck(:id)
      merge_supporters!(supporter, into: merge_into)
      supporter.update!(
        status: "duplicate",
        potential_duplicate: false,
        duplicate_of_id: merge_into.id,
        duplicate_checked_at: Time.current,
        duplicate_notes: "Merged into supporter ##{merge_into.id}"
      )
      reconcile_active_duplicates!(impacted_active_ids)
    end
  end

  def self.remove_candidate!(supporter)
    impacted_supporter_ids = find_duplicates(supporter).pluck(:id)

    supporter.update_columns(
      potential_duplicate: false,
      duplicate_of_id: nil,
      duplicate_checked_at: Time.current,
      duplicate_notes: nil
    )

    reconcile_duplicate_candidates!(impacted_supporter_ids)
  end

  # Scan all supporters for duplicates using bulk SQL queries.
  # Returns the number of newly flagged duplicates.
  def self.scan_all!
    count = 0

    # Reset unresolved flags first so the scan becomes a full recomputation.
    Supporter.where(potential_duplicate: true).update_all(
      potential_duplicate: false,
      duplicate_of_id: nil,
      duplicate_notes: nil,
      duplicate_checked_at: Time.current
    )

    # Phase 1: Find phone duplicates in bulk via SQL
    phone_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'phone' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.normalized_phone = s2.normalized_phone
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
        AND s1.normalized_phone IS NOT NULL
        AND s1.normalized_phone != ''
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
      GROUP BY s1.id
    SQL

    # Phase 2: Find email duplicates in bulk via SQL
    email_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'email' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON LOWER(s1.email) = LOWER(s2.email)
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
        AND s1.email IS NOT NULL
        AND s1.email != ''
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
      GROUP BY s1.id
    SQL

    # Phase 3: Find shared GEC voter links in bulk via SQL
    gec_link_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'same GEC voter' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.gec_voter_id = s2.gec_voter_id
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
        AND s1.gec_voter_id IS NOT NULL
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
      GROUP BY s1.id
    SQL

    # Phase 4: Find name + DOB duplicates in bulk via SQL
    dob_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+dob' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.dob = s2.dob
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.first_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.last_name))
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
        AND s1.dob IS NOT NULL
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
        AND s1.first_name IS NOT NULL
        AND s1.last_name IS NOT NULL
      GROUP BY s1.id
    SQL

    # Phase 5: Find name + exact street-address duplicates in bulk via SQL.
    # Per-record checks use AddressNormalizer; this exact bulk scan is a
    # conservative catch-up pass for existing data.
    address_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+address' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON LOWER(TRIM(s1.street_address)) = LOWER(TRIM(s2.street_address))
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.first_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.last_name))
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
        AND s1.street_address IS NOT NULL
        AND s1.street_address != ''
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
        AND s1.first_name IS NOT NULL
        AND s1.last_name IS NOT NULL
      GROUP BY s1.id
    SQL

    # Phase 6: Find name+village duplicates in bulk via SQL
    name_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+village' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.village_id = s2.village_id
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.first_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.last_name))
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.review_status != 'rejected'
        AND s2.review_status != 'rejected'
        AND s1.public_review_status != 'rejected'
        AND s2.public_review_status != 'rejected'
        AND s1.first_name IS NOT NULL
        AND s1.last_name IS NOT NULL
      GROUP BY s1.id
    SQL

    # Phase 7: Also check swapped names (First entered as Last, etc.)
    swapped_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+village (swapped)' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.village_id = s2.village_id
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.last_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.first_name))
        AND s1.id > s2.id
        AND NOT EXISTS (
          SELECT 1 FROM duplicate_pair_dismissals dpd
          WHERE dpd.supporter_id = s2.id
            AND dpd.dismissed_supporter_id = s1.id
        )
      WHERE s1.status = 'active'
        AND s2.status = 'active'
        AND s1.first_name IS NOT NULL
        AND s1.last_name IS NOT NULL
      GROUP BY s1.id
    SQL

    # Merge all results: supporter_id -> { matches: { match_id => [types] } }
    # Track each match_id separately so notes accurately reflect which record
    # matched on which criteria.
    all_dupes = {}
    [ phone_dupes, email_dupes, gec_link_dupes, dob_dupes, address_dupes, name_dupes, swapped_dupes ].each do |result_set|
      result_set.each do |row|
        sid = row["supporter_id"]
        mid = row["match_id"]
        mtype = row["match_type"]
        all_dupes[sid] ||= {}
        all_dupes[sid][mid] ||= []
        all_dupes[sid][mid] << mtype
      end
    end

    # Collect all target IDs that need reverse-flagging
    reverse_flags = {} # match_id -> [supporter_ids that reference it]

    # Update all flagged supporters
    all_dupes.each do |supporter_id, matches|
      # Build accurate notes: each match_id gets its own match types
      reasons = matches.map do |mid, types|
        "##{mid} (#{types.uniq.join(', ')})"
      end
      notes = "Matches: #{reasons.join('; ')}"

      # Link to the oldest matching supporter
      oldest_match_id = matches.keys.min

      updated = Supporter.where(id: supporter_id)
                         .where(potential_duplicate: false)
                         .update_all(
                           potential_duplicate: true,
                           duplicate_of_id: oldest_match_id,
                           duplicate_notes: notes
                         )
      count += updated

      # Track reverse flags (batch them to avoid redundant updates)
      matches.each_key do |match_id|
        reverse_flags[match_id] ||= []
        reverse_flags[match_id] << supporter_id
      end
    end

    # Batch reverse-flag match targets (skip any already in all_dupes — they were handled above)
    reverse_flags.each do |match_id, referencing_ids|
      next if all_dupes.key?(match_id) # Already flagged above

      Supporter.where(id: match_id)
               .where(potential_duplicate: false)
               .update_all(
                 potential_duplicate: true,
                 duplicate_of_id: referencing_ids.min,
                 duplicate_notes: "Has #{referencing_ids.size} potential duplicate(s) — see ##{referencing_ids.join(', #')}"
               )
    end

    count
  end

  private_class_method def self.dismiss_duplicate_pair!(supporter, dismissed_match: nil, resolved_by: nil)
    dismissed_match_ids = if dismissed_match
      [ dismissed_match.id ]
    elsif supporter.duplicate_of_id.present?
      [ supporter.duplicate_of_id ]
    else
      Supporter.where(duplicate_of_id: supporter.id).order(:created_at, :id).limit(1).pluck(:id)
    end
    dismissed_match_ids = dismissed_match_ids.compact.uniq

    dismissed_match_ids.each do |match_id|
      DuplicatePairDismissal.create_for_pair!(
        supporter.id,
        match_id,
        resolved_by: resolved_by,
        note: "Dismissed — not a duplicate"
      )
    end

    impacted_ids = [ supporter.id ] + dismissed_match_ids
    impacted_ids.concat(Supporter.where(duplicate_of_id: impacted_ids).pluck(:id))
    reconcile_duplicate_candidates!(impacted_ids.uniq)
  end

  private_class_method def self.address_duplicate_ids(supporter, active_scope:, first_name:, last_name:)
    return [] if supporter.street_address.blank?

    supporter_key = canonical_address_key(supporter)
    return [] if supporter_key.blank?

    active_scope.where.not(street_address: [ nil, "" ])
                .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?", first_name, last_name)
                .includes(:village)
                .select { |candidate| canonical_address_key(candidate) == supporter_key }
                .map(&:id)
  end

  private_class_method def self.canonical_address_key(supporter)
    AddressNormalizer.canonical_address(supporter.street_address, village_name: supporter.village&.name)
  end

  private_class_method def self.same_name?(left, right)
    left.first_name&.downcase == right.first_name&.downcase && left.last_name&.downcase == right.last_name&.downcase
  end

  private_class_method def self.same_address?(left, right)
    left_key = canonical_address_key(left)
    left_key.present? && left_key == canonical_address_key(right)
  end

  private_class_method def self.build_notes(supporter, duplicates)
    reasons = []
    duplicates.each do |dup|
      matching = []
      matching << "phone" if dup.normalized_phone.present? && dup.normalized_phone == supporter.normalized_phone
      matching << "email" if dup.email.present? && supporter.email.present? && dup.email.downcase == supporter.email.downcase
      matching << "same GEC voter" if supporter.gec_voter_id.present? && dup.gec_voter_id == supporter.gec_voter_id
      matching << "name+dob" if supporter.dob.present? && dup.dob == supporter.dob && same_name?(supporter, dup)
      matching << "name+address" if same_name?(supporter, dup) && same_address?(supporter, dup)
      matching << "name+village" if dup.village_id == supporter.village_id &&
                                     dup.first_name&.downcase == supporter.first_name&.downcase &&
                                     dup.last_name&.downcase == supporter.last_name&.downcase
      matching << "name+village (swapped)" if dup.village_id == supporter.village_id &&
                                               dup.first_name&.downcase == supporter.last_name&.downcase &&
                                               dup.last_name&.downcase == supporter.first_name&.downcase
      reasons << "##{dup.id} (#{matching.join(', ')})"
    end
    "Matches: #{reasons.join('; ')}"
  end

  private_class_method def self.reconcile_active_duplicates!(supporter_ids)
    reconcile_duplicate_candidates!(supporter_ids)
  end

  private_class_method def self.reconcile_duplicate_candidates!(supporter_ids)
    supporter_ids.each do |supporter_id|
      supporter = Supporter.duplicate_review_candidates.find_by(id: supporter_id)
      next unless supporter

      duplicates = find_duplicates(supporter).to_a
      if duplicates.any?
        original = duplicates.min_by { |record| [ record.created_at, record.id ] }
        supporter.update_columns(
          potential_duplicate: true,
          duplicate_of_id: original.id,
          duplicate_checked_at: nil,
          duplicate_notes: build_notes(supporter, duplicates)
        )
      else
        supporter.update_columns(
          potential_duplicate: false,
          duplicate_of_id: nil,
          duplicate_checked_at: Time.current,
          duplicate_notes: nil
        )
      end
    end
  end

  private_class_method def self.merge_supporters!(source, into:)
    # Transfer contact attempts
    source.supporter_contact_attempts.update_all(supporter_id: into.id)

    # Preserve useful DPG contact intelligence from both records. A duplicate
    # signup often contains newer help requests or opt-ins, so merging should
    # not accidentally lose voter-help/volunteer signals.
    copy_blank_fields!(source, into: into)
    preserve_affirmative_signals!(source, into: into)
    preserve_stronger_statuses!(source, into: into)
    into.save! if into.changed?
  end

  private_class_method def self.copy_blank_fields!(source, into:)
    %w[email contact_number street_address dob gec_voter_id verification_reason verification_reason_metadata].each do |field|
      next unless into.public_send(field).blank? && source.public_send(field).present?

      into.public_send("#{field}=", source.public_send(field))
    end

    into.registered_voter = source.registered_voter if into.registered_voter.nil? && !source.registered_voter.nil?

    if into.verification_status != "verified" && source.verification_status == "verified"
      into.verification_status = source.verification_status
      into.verified_at = source.verified_at if source.verified_at.present?
      into.verified_by_user_id = source.verified_by_user_id if source.verified_by_user_id.present?
    end
  end

  private_class_method def self.preserve_affirmative_signals!(source, into:)
    if source.self_reported_registered_voter == true && into.self_reported_registered_voter.nil? && into.registered_voter != false && into.registered_voter_status != "no"
      into.self_reported_registered_voter = true
    end

    %w[
      opt_in_email
      opt_in_text
      wants_to_volunteer
      needs_absentee_ballot_help
      needs_homebound_voting_help
      needs_voter_registration_help
      needs_election_day_ride
    ].each do |field|
      into.public_send("#{field}=", true) if source.public_send(field) == true && into.public_send(field) != true
    end
  end

  private_class_method def self.preserve_stronger_statuses!(source, into:)
    if into.support_status == "unknown" && source.support_status.present? && source.support_status != "unknown"
      into.support_status = source.support_status
    end

    volunteer_rank = { "unknown" => 0, "not_interested" => 1, "interested" => 2, "active" => 3 }
    if volunteer_rank.fetch(source.volunteer_status, 0) > volunteer_rank.fetch(into.volunteer_status, 0)
      into.volunteer_status = source.volunteer_status
    end

    if into.registered_voter != false && into.self_reported_registered_voter.nil? && [ nil, "", "not_sure" ].include?(into.registered_voter_status) && source.registered_voter_status.present? && source.registered_voter_status != "not_sure"
      into.registered_voter_status = source.registered_voter_status
    end
  end
end
