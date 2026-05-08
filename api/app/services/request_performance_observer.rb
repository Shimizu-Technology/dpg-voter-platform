class RequestPerformanceObserver
  IGNORED_SQL_EVENT_NAMES = [ "SCHEMA" ].freeze

  Result = Struct.new(:duration_ms, :sql_query_count, keyword_init: true)

  def self.capture
    query_count = 0
    started_at = nil
    metrics = nil
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      next if IGNORED_SQL_EVENT_NAMES.include?(payload[:name]) || payload[:cached]

      query_count += 1
    end

    begin
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      duration_ms = if started_at
        ((finished_at - started_at) * 1000.0).round(2)
      else
        0.0
      end
      metrics = Result.new(duration_ms: duration_ms, sql_query_count: query_count)
    end

    metrics
  end
end
