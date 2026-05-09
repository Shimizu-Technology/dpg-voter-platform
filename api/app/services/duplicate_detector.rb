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

    # 3. Name + village match (uses composite index)
    if supporter.first_name.present? && supporter.last_name.present? && supporter.village_id.present?
      fn = supporter.first_name.downcase.strip
      ln = supporter.last_name.downcase.strip

      # Exact name match in same village
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

    Supporter.duplicate_review_candidates.where(id: match_ids.to_a)
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
  def self.resolve!(supporter, action:, merge_into: nil, resolved_by: nil)
    case action
    when "dismiss"
      supporter.update!(
        potential_duplicate: false,
        duplicate_of_id: nil,
        duplicate_checked_at: Time.current,
        duplicate_notes: "Dismissed — not a duplicate"
      )
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

    # Phase 3: Find name+village duplicates in bulk via SQL
    name_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+village' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.village_id = s2.village_id
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.first_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.last_name))
        AND s1.id > s2.id
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

    # Phase 4: Also check swapped names (First entered as Last, etc.)
    swapped_dupes = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT s1.id AS supporter_id, MIN(s2.id) AS match_id, 'name+village (swapped)' AS match_type
      FROM supporters s1
      JOIN supporters s2
        ON s1.village_id = s2.village_id
        AND LOWER(TRIM(s1.first_name)) = LOWER(TRIM(s2.last_name))
        AND LOWER(TRIM(s1.last_name)) = LOWER(TRIM(s2.first_name))
        AND s1.id > s2.id
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
    [ phone_dupes, email_dupes, name_dupes, swapped_dupes ].each do |result_set|
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

  private_class_method def self.build_notes(supporter, duplicates)
    reasons = []
    duplicates.each do |dup|
      matching = []
      matching << "phone" if dup.normalized_phone.present? && dup.normalized_phone == supporter.normalized_phone
      matching << "email" if dup.email.present? && supporter.email.present? && dup.email.downcase == supporter.email.downcase
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

    # Merge fields with field-specific rules:
    # - text fields copy into blank slots
    # - authoritative voter lookup only fills nil
    # - self-reported/preferences preserve any affirmative signal
    mergeable = %w[email registered_voter self_reported_registered_voter opt_in_email opt_in_text]
    mergeable.each do |field|
      into_val = into.send(field)
      source_val = source.send(field)

      should_copy =
        case field
        when "email"
          into_val.blank? && source_val.present?
        when "registered_voter"
          into_val.nil? && !source_val.nil?
        else
          (source_val == true && into_val != true) || (into_val.nil? && !source_val.nil?)
        end

      if should_copy
        into.send("#{field}=", source_val)
      end
    end
    into.save! if into.changed?
  end
end
