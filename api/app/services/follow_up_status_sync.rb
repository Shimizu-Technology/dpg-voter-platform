# frozen_string_literal: true

class FollowUpStatusSync
  def self.contact_attempt_updates(supporter, contact_attempt)
    new(supporter, contact_attempt).contact_attempt_updates
  end

  def initialize(supporter, contact_attempt)
    @supporter = supporter
    @contact_attempt = contact_attempt
  end

  def contact_attempt_updates
    updates = {}
    timestamp = @contact_attempt.recorded_at || Time.current

    if registration_follow_up_needed? && @supporter.registration_outreach_status.blank?
      updates[:registration_outreach_status] = "contacted"
      updates[:registration_outreach_date] = timestamp
    end

    if voter_help_follow_up_needed? && @supporter.support_follow_up_status.blank?
      updates[:support_follow_up_status] = "in_progress"
      updates[:support_follow_up_date] = timestamp
    end

    updates
  end

  private

  def registration_follow_up_needed?
    @supporter.registered_voter == false ||
      @supporter.registered_voter_status.in?(%w[no not_sure]) ||
      @supporter.needs_voter_registration_help?
  end

  def voter_help_follow_up_needed?
    @supporter.wants_to_volunteer? ||
      @supporter.volunteer_status == "interested" ||
      @supporter.needs_absentee_ballot_help? ||
      @supporter.needs_homebound_voting_help? ||
      @supporter.needs_election_day_ride?
  end
end
