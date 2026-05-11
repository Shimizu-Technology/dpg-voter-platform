class Supporter < ApplicationRecord
  ATTRIBUTION_METHODS = %w[qr_self_signup staff_manual staff_scan bulk_import public_signup].freeze
  INTAKE_STATUSES = %w[accepted pending_public_review].freeze
  CONTACT_CLASSIFICATIONS = %w[
    new_intake
    active_contact
    supporter
    member
    volunteer
    undecided
    not_supporting
    duplicate
    invalid
    archived
  ].freeze
  REVIEW_STATUSES = %w[pending approved rejected].freeze
  PUBLIC_REVIEW_STATUSES = %w[not_applicable pending approved rejected].freeze
  REGISTERED_VOTER_STATUSES = %w[yes no not_sure].freeze
  SUPPORT_FOLLOW_UP_STATUSES = %w[in_progress completed declined].freeze
  TURNOUT_STATUSES = %w[unknown not_yet_voted voted observed_elsewhere].freeze
  TURNOUT_SOURCES = %w[data_team admin_override].freeze
  VERIFICATION_STATUSES = %w[unverified verified flagged].freeze
  VERIFICATION_REASONS = %w[
    matched_current_gec
    village_mismatch
    multiple_matches
    fuzzy_name_match
    low_confidence_match
    needs_manual_review
    no_gec_match
    manual_staff_flag
    manual_staff_verified
  ].freeze

  belongs_to :village
  belongs_to :submitted_village, class_name: "Village", optional: true
  belongs_to :referred_from_village, class_name: "Village", optional: true
  belongs_to :precinct, optional: true
  belongs_to :gec_voter, optional: true
  belongs_to :block, optional: true
  belongs_to :household_group, optional: true
  belongs_to :referral_code, optional: true
  belongs_to :entered_by, class_name: "User", foreign_key: :entered_by_user_id, optional: true
  belongs_to :turnout_updated_by_user, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", foreign_key: :verified_by_user_id, optional: true
  belongs_to :reviewed_by, class_name: "User", foreign_key: :reviewed_by_user_id, optional: true
  belongs_to :public_reviewed_by, class_name: "User", foreign_key: :public_reviewed_by_user_id, optional: true
  belongs_to :classified_by_user, class_name: "User", optional: true
  belongs_to :duplicate_of, class_name: "Supporter", foreign_key: :duplicate_of_id, optional: true
  has_many :duplicates, class_name: "Supporter", foreign_key: :duplicate_of_id, dependent: :nullify

  has_many :audit_logs, as: :auditable, dependent: :destroy
  has_many :supporter_contact_attempts, dependent: :destroy

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :contact_number, presence: true, unless: :phone_optional_entry?

  # Keep print_name in sync as "Last, First" for display and backward compatibility
  before_validation :sync_print_name
  before_validation :sync_review_workflow_fields
  before_validation :sync_registered_voter_status
  before_validation :sync_submitted_village
  before_validation :sync_precinct_assignment
  before_save :set_normalized_phone
  after_create :check_for_duplicates
  after_create :auto_vet_against_gec

  def display_name
    NameParser.combine(first_name: first_name, middle_name: middle_name, last_name: last_name)
  end
  validates :status, inclusion: { in: %w[active inactive duplicate unverified removed] }
  # "referral" kept for backward compatibility with legacy records
  validates :source, inclusion: { in: %w[staff_entry qr_signup referral bulk_import public_signup] }, allow_nil: true
  # DB column is NOT NULL with default "public_signup", but allow_nil guards against
  # in-memory objects that haven't been persisted yet (e.g. during validation checks).
  validates :attribution_method, inclusion: { in: ATTRIBUTION_METHODS }, allow_nil: true
  validates :intake_status, inclusion: { in: INTAKE_STATUSES }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :public_review_status, inclusion: { in: PUBLIC_REVIEW_STATUSES }
  validates :registered_voter_status, inclusion: { in: REGISTERED_VOTER_STATUSES }
  validates :contact_classification, inclusion: { in: CONTACT_CLASSIFICATIONS }
  validates :support_follow_up_status, inclusion: { in: SUPPORT_FOLLOW_UP_STATUSES }, allow_nil: true
  validates :turnout_status, inclusion: { in: TURNOUT_STATUSES }
  validates :turnout_source, inclusion: { in: TURNOUT_SOURCES }, allow_blank: true
  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
  validates :verification_reason, inclusion: { in: VERIFICATION_REASONS }, allow_nil: true
  validate :precinct_matches_village
  validate :block_matches_village

  scope :active, -> { where(status: "active") }
  scope :contacts, -> { active.where.not(contact_classification: %w[archived invalid duplicate]) }
  scope :intake, -> { contacts.where(contact_classification: "new_intake") }
  scope :classified_supporters, -> { contacts.where(contact_classification: "supporter") }
  scope :members, -> { contacts.where(contact_classification: "member") }
  scope :volunteers, -> { contacts.where(contact_classification: "volunteer") }
  scope :verified, -> { where(verification_status: "verified") }
  scope :unverified, -> { where(verification_status: "unverified") }
  scope :flagged, -> { where(verification_status: "flagged") }
  scope :registered_voters, -> { where(registered_voter: true) }

  # Pipeline separation: team input vs public signups (supplemental)
  TEAM_SOURCES = %w[staff_entry bulk_import].freeze
  PUBLIC_SOURCES = %w[public_signup qr_signup].freeze
  scope :accepted_intake, -> { active.where(review_status: "approved") }
  scope :review_pending, -> { where(review_status: "pending") }
  scope :review_approved, -> { where(review_status: "approved") }
  scope :review_rejected, -> { where(review_status: "rejected") }
  scope :duplicate_review_candidates, -> {
    active.where.not(review_status: "rejected").where.not(public_review_status: "rejected")
  }
  scope :pending_public_review, -> { where(public_review_status: "pending", source: PUBLIC_SOURCES) }
  scope :public_review_approved, -> { where(public_review_status: "approved", source: PUBLIC_SOURCES) }
  scope :public_review_rejected, -> { where(public_review_status: "rejected", source: PUBLIC_SOURCES) }
  scope :public_origin, -> { where(source: PUBLIC_SOURCES) }
  scope :accepted_public_signups, -> { public_origin.review_approved }
  scope :engaged_contacts, -> { contacts.where(contact_classification: %w[active_contact supporter member volunteer undecided]) }
  scope :official_supporters, -> { contacts.where(contact_classification: %w[supporter member volunteer]) }
  scope :pending_supporter_review, -> { active.review_pending.where(public_review_status: %w[approved not_applicable]) }
  scope :working_supporters, -> { official_supporters }
  scope :team_input, -> { official_supporters.where(source: TEAM_SOURCES) }
  scope :public_signups, -> { public_origin }
  scope :submitted_village_referrals, -> {
    where.not(submitted_village_id: nil)
      .where("supporters.submitted_village_id <> supporters.village_id")
  }
  scope :with_household, -> { where.not(household_group_id: nil) }
  scope :registered_voter_status_is, ->(status) { where(registered_voter_status: status) }
  # Legacy broad voter-help scope retained for existing list/report usage.
  # This still includes voter registration help; new support-track follow-up
  # code should prefer `needs_support_services` to exclude registration work.
  scope :needs_campaign_help, -> {
    where(
      wants_to_volunteer: true
    ).or(where(needs_absentee_ballot_help: true))
      .or(where(needs_homebound_voting_help: true))
      .or(where(needs_voter_registration_help: true))
      .or(where(needs_election_day_ride: true))
  }
  # Support-track follow-up only: excludes registration-help requests so the
  # registration and support queues remain independent.
  scope :needs_support_services, -> {
    where(wants_to_volunteer: true)
      .or(where(needs_absentee_ballot_help: true))
      .or(where(needs_homebound_voting_help: true))
      .or(where(needs_election_day_ride: true))
  }
  scope :needs_follow_up, -> {
    where(registered_voter_status: %w[no not_sure])
      .or(where(registered_voter: false))
      .or(where(needs_voter_registration_help: true))
      .or(needs_support_services)
  }
  scope :potential_duplicates_only, -> { duplicate_review_candidates.where(potential_duplicate: true) }
  scope :today, -> { where("supporters.created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("supporters.created_at >= ?", Time.current.beginning_of_week) }
  # Verification-time windows for vetted metrics.
  # Fallback to created_at for legacy verified rows missing verified_at.
  scope :verified_today, -> {
    verified.where("COALESCE(supporters.verified_at, supporters.created_at) >= ?", Time.current.beginning_of_day)
  }
  scope :verified_this_week, -> {
    verified.where("COALESCE(supporters.verified_at, supporters.created_at) >= ?", Time.current.beginning_of_week)
  }

  def self.potential_duplicates(name, village_id, first_name: nil, last_name: nil)
    return none if village_id.blank?

    scope = where(village_id: village_id).duplicate_review_candidates

    if first_name.present? && last_name.present?
      scope.where("LOWER(first_name) = ? AND LOWER(last_name) = ?", first_name.downcase.strip, last_name.downcase.strip)
    elsif name.present?
      scope.where("LOWER(print_name) = ?", name.downcase.strip)
    else
      none
    end
  end

  def submitted_village_referral?
    submitted_village_id.present? && village_id.present? && submitted_village_id != village_id
  end

  def household_members
    return [] unless household_group_id.present?
    return [] unless household_group.present?

    household_group.supporters.to_a.reject { |member| member.id == id }
  end

  private

  def phone_optional_entry?
    # Imports and staff-assisted entries may legitimately lack phone numbers.
    %w[staff_manual staff_scan bulk_import].include?(attribution_method)
  end

  def sync_print_name
    # If first/last are blank but print_name was provided, auto-split for backward compatibility
    if first_name.blank? && last_name.blank? && print_name.present?
      parts = NameParser.split_print_name(print_name)
      self.first_name = parts[:first_name]
      self.middle_name = parts[:middle_name]
      self.last_name = parts[:last_name].presence || parts[:first_name]
    end

    # Keep print_name in sync from first/middle/last
    self.print_name = NameParser.combine(
      first_name: first_name,
      middle_name: middle_name,
      last_name: last_name,
      format: :last_comma_first
    ).presence
  end

  def sync_review_workflow_fields
    if PUBLIC_SOURCES.include?(source)
      if public_review_status == "rejected" || review_status == "rejected"
        self.public_review_status = "rejected"
        self.review_status = "rejected"
      elsif intake_status == "pending_public_review"
        self.public_review_status = "pending"
        self.review_status = "pending"
      else
        self.public_review_status = "not_applicable"
        self.review_status = review_status.presence || "approved"
      end
    else
      self.public_review_status = "not_applicable"
      self.review_status = review_status.presence || "approved"
    end
  end

  def sync_registered_voter_status
    if will_save_change_to_self_reported_registered_voter?
      self.registered_voter_status =
        case self_reported_registered_voter
        when true
          "yes"
        when false
          "no"
        else
          "not_sure"
        end
    else
      self.registered_voter_status =
        if registered_voter_status.present?
          registered_voter_status
        elsif self_reported_registered_voter == true
          "yes"
        elsif self_reported_registered_voter == false
          "no"
        else
          "not_sure"
        end

      self.self_reported_registered_voter =
        case registered_voter_status
        when "yes"
          true
        when "no"
          false
        else
          nil
        end
    end
  end

  def sync_submitted_village
    self.submitted_village_id ||= village_id
  end

  def precinct_matches_village
    return if precinct.blank? || village_id.blank?
    return if precinct.village_id == village_id

    errors.add(:precinct_id, "must belong to the selected village")
  end

  def block_matches_village
    return if block.blank? || village_id.blank?
    return if block.village_id == village_id

    errors.add(:block_id, "must belong to the selected village")
  end

  # Keep precinct assignment aligned with the selected village. On create we
  # auto-fill blanks; on update we re-fill only when the village changes or the
  # precinct was explicitly cleared, so manual selections remain respected.
  def sync_precinct_assignment
    if village_id.blank?
      self.precinct_id = nil
      return
    end

    return if precinct_id.present?
    return unless new_record? || will_save_change_to_village_id? || will_save_change_to_precinct_id?

    self.precinct_id = PrecinctAssigner.assign_id(self)
  end

  def set_normalized_phone
    self.normalized_phone = self.class.normalize_phone(contact_number)
  end

  def check_for_duplicates
    DuplicateDetector.flag_if_duplicate!(self)
  rescue StandardError => e
    Rails.logger.warn("Duplicate detection failed for supporter #{id}: #{e.message}")
  end

  def auto_vet_against_gec
    result = GecVettingService.new(self).call
    Rails.logger.info("GEC vetting for supporter #{id}: #{result.status} — #{result.details}")
  rescue StandardError => e
    Rails.logger.warn("GEC vetting failed for supporter #{id}: #{e.message}")
  end

  # Class method so DuplicateDetector can also use it
  def self.normalize_phone(phone)
    return nil if phone.blank?
    digits = phone.gsub(/\D/, "")
    # Normalize Guam numbers: strip leading country code (1 or +1)
    # Only strip if the result is a valid 10-digit Guam number (671 + 7 digits)
    if digits.length >= 11 && digits.start_with?("1671")
      digits = digits[1..] # Strip leading "1"
    end
    digits
  end
end
