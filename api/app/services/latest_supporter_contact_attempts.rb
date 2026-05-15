# frozen_string_literal: true

class LatestSupporterContactAttempts
  def self.call(supporters_or_ids, include_recorded_by: false)
    new(supporters_or_ids, include_recorded_by: include_recorded_by).call
  end

  def initialize(supporters_or_ids, include_recorded_by:)
    @supporter_ids = Array(supporters_or_ids).map { |item| item.respond_to?(:id) ? item.id : item }.compact
    @include_recorded_by = include_recorded_by
  end

  def call
    return {} if @supporter_ids.empty?

    scope = SupporterContactAttempt
      .from(ranked_attempts, :supporter_contact_attempts)
      .where("attempt_rank = 1")
    scope = scope.includes(:recorded_by_user) if @include_recorded_by

    scope.each_with_object({}) do |attempt, latest_by_supporter|
      latest_by_supporter[attempt.supporter_id] = attempt
    end
  end

  private

  def ranked_attempts
    SupporterContactAttempt
      .select(
        "supporter_contact_attempts.*, " \
        "ROW_NUMBER() OVER (PARTITION BY supporter_id ORDER BY recorded_at DESC, id DESC) AS attempt_rank"
      )
      .where(supporter_id: @supporter_ids)
  end
end
