# frozen_string_literal: true

class ElectionDayCommandCenterQuery
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100
  CONTACT_FILTERS = %w[all not_contacted contacted rides].freeze

  attr_reader :event, :params

  def initialize(event:, params: {})
    @event = event
    @params = params
  end

  def stats
    turnout = turnout_counts
    chase = chase_scope
    contacted = chase.where(id: contacted_today_ids).count

    {
      total_voters: turnout.values.sum,
      voted: turnout.fetch("voted", 0),
      not_yet_voted: turnout.fetch("not_yet_voted", 0),
      unknown: turnout.fetch("unknown", 0),
      observed_elsewhere: turnout.fetch("observed_elsewhere", 0),
      chase_list_count: chase.count,
      contacted_today: contacted,
      not_contacted_today: chase.where.not(id: contacted_today_ids).count,
      ride_requests: chase.where(needs_election_day_ride: true).count,
      exceptions: event.election_turnout_records.observed_elsewhere.count
    }
  end

  def villages
    turnout_by_village = voter_scope
      .joins(turnout_join_sql)
      .group(Arel.sql(gec_village_sql), Arel.sql(effective_turnout_status_sql))
      .count
    linked_by_village = linked_contact_scope.group(Arel.sql(gec_village_sql)).count
    chase_by_village = chase_scope.group(Arel.sql(gec_village_sql)).count
    contacted_by_village = chase_scope.where(id: contacted_today_ids).group(Arel.sql(gec_village_sql)).count
    rides_by_village = chase_scope.where(needs_election_day_ride: true).group(Arel.sql(gec_village_sql)).count

    village_names = turnout_by_village.keys.map(&:first).uniq.sort
    village_names.map do |name|
      total = turnout_by_village.sum { |(village, _status), count| village == name ? count : 0 }
      linked_not_yet = chase_by_village.fetch(name, 0)
      contacted = contacted_by_village.fetch(name, 0)
      {
        name: name,
        total_voters: total,
        voted: turnout_by_village.fetch([ name, "voted" ], 0),
        not_yet_voted: turnout_by_village.fetch([ name, "not_yet_voted" ], 0),
        unknown: turnout_by_village.fetch([ name, "unknown" ], 0),
        observed_elsewhere: turnout_by_village.fetch([ name, "observed_elsewhere" ], 0),
        linked_contacts: linked_by_village.fetch(name, 0),
        linked_not_yet_voted: linked_not_yet,
        contacted_today: contacted,
        not_contacted_today: [ linked_not_yet - contacted, 0 ].max,
        ride_requests: rides_by_village.fetch(name, 0)
      }
    end
  end

  def chase_page
    scope = filtered_chase_scope
    total = scope.count
    pages = (total.to_f / per_page).ceil
    current_page = pages.positive? ? [ page, pages ].min : 1
    page_records = scope
      .includes(:village, :precinct, gec_voter: [ :village, :precinct ])
      .order(
        Arel.sql("LOWER(COALESCE(gec_voters.village_name, '')) ASC"),
        Arel.sql("LOWER(COALESCE(supporters.last_name, '')) ASC"),
        Arel.sql("LOWER(COALESCE(supporters.first_name, '')) ASC"),
        Arel.sql("supporters.id ASC")
      )
      .limit(per_page)
      .offset((current_page - 1) * per_page)
      .to_a
    latest_attempts = LatestSupporterContactAttempts.call(page_records, include_recorded_by: true)

    {
      records: page_records.map { |supporter| chase_payload(supporter, latest_attempts[supporter.id]) },
      pagination: {
        page: current_page,
        per_page: per_page,
        total: total,
        pages: pages
      }
    }
  end

  private

  def voter_scope
    @voter_scope ||= begin
      scope = GecVoter.active
      event.gec_list_date.present? ? scope.for_list_date(event.gec_list_date) : scope.election_day_active
    end
  end

  def turnout_counts
    @turnout_counts ||= voter_scope
      .joins(turnout_join_sql)
      .group(Arel.sql(effective_turnout_status_sql))
      .count
  end

  def linked_contact_scope
    @linked_contact_scope ||= Supporter.contacts
      .joins(:gec_voter)
      .where(gec_voter_id: voter_scope.select(:id))
  end

  def chase_scope
    @chase_scope ||= linked_contact_scope
      .joins(turnout_join_sql)
      .where("command_turnout_records.turnout_status = 'not_yet_voted' OR command_turnout_records.id IS NULL")
  end

  def filtered_chase_scope
    scope = chase_scope.left_joins(:village)
    if village_filter.present?
      scope = scope.where(
        "LOWER(COALESCE(gec_voters.village_name, '')) = :village OR LOWER(COALESCE(villages.name, '')) = :village",
        village: village_filter.downcase
      )
    end
    if search.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(search.downcase)}%"
      scope = scope.where(
        <<~SQL.squish,
          LOWER(COALESCE(supporters.first_name, '')) LIKE :term
          OR LOWER(COALESCE(supporters.middle_name, '')) LIKE :term
          OR LOWER(COALESCE(supporters.last_name, '')) LIKE :term
          OR LOWER(COALESCE(supporters.contact_number, '')) LIKE :term
          OR LOWER(COALESCE(supporters.email, '')) LIKE :term
        SQL
        term: term
      )
    end

    case contact_filter
    when "not_contacted"
      scope.where.not(id: contacted_today_ids)
    when "contacted"
      scope.where(id: contacted_today_ids)
    when "rides"
      scope.where(needs_election_day_ride: true)
    else
      scope
    end
  end

  def contacted_today_ids
    @contacted_today_ids ||= SupporterContactAttempt
      .where(recorded_at: Time.zone.today.all_day)
      .distinct
      .pluck(:supporter_id)
  end

  def turnout_join_sql
    @turnout_join_sql ||= ActiveRecord::Base.sanitize_sql_array([
      <<~SQL.squish,
        LEFT OUTER JOIN election_turnout_records command_turnout_records
          ON command_turnout_records.gec_voter_id = gec_voters.id
          AND command_turnout_records.election_event_id = ?
      SQL
      event.id
    ])
  end

  def effective_turnout_status_sql
    "COALESCE(command_turnout_records.turnout_status, 'not_yet_voted')"
  end

  def gec_village_sql
    "COALESCE(NULLIF(gec_voters.village_name, ''), 'Unknown')"
  end

  def chase_payload(supporter, latest_attempt)
    voter = supporter.gec_voter
    {
      supporter_id: supporter.id,
      gec_voter_id: voter.id,
      name: supporter.display_name,
      phone: supporter.contact_number,
      email: supporter.email,
      dpg_village: supporter.village&.name,
      dpg_precinct: supporter.precinct&.number,
      gec_village: voter.village_name || voter.village&.name,
      gec_precinct: voter.precinct_number || voter.precinct&.number,
      turnout_status: "not_yet_voted",
      needs_ride: supporter.needs_election_day_ride,
      support_status: supporter.support_status,
      latest_contact_attempt: latest_attempt && contact_attempt_summary(latest_attempt),
      contacted_today: latest_attempt&.recorded_at&.to_date == Time.zone.today
    }
  end

  def contact_attempt_summary(attempt)
    {
      id: attempt.id,
      channel: attempt.channel,
      outcome: attempt.outcome,
      note: attempt.note,
      recorded_at: attempt.recorded_at&.iso8601,
      recorded_by_name: attempt.recorded_by_user&.name
    }
  end

  def village_filter
    params[:village].to_s.strip
  end

  def search
    params[:search].to_s.strip
  end

  def contact_filter
    value = params[:contact_filter].to_s
    CONTACT_FILTERS.include?(value) ? value : "not_contacted"
  end

  def page
    [ params[:chase_page].to_i, 1 ].max
  end

  def per_page
    requested = params[:chase_per_page].to_i
    requested = DEFAULT_PER_PAGE if requested <= 0
    [ requested, MAX_PER_PAGE ].min
  end
end
