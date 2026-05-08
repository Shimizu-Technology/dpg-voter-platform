class ApplicationController < ActionController::API
  around_action :track_request_performance

  private

  def track_request_performance
    return yield unless request_performance_observability_enabled?

    result = RequestPerformanceObserver.capture { yield }
    append_request_performance_headers(result)
    log_request_performance(result)
  end

  def request_performance_observability_enabled?
    return false if Rails.env.test?
    return ActiveModel::Type::Boolean.new.cast(ENV.fetch("REQUEST_PERF_OBSERVABILITY", "false")) if Rails.env.production?

    true
  end

  def append_request_performance_headers(result)
    response.set_header("X-Request-Duration-Ms", result.duration_ms.to_s)
    response.set_header("X-SQL-Query-Count", result.sql_query_count.to_s)
  end

  def log_request_performance(result)
    severity = result.duration_ms >= request_slow_threshold_ms ? :warn : :info
    Rails.logger.public_send(severity, {
      event: "api_request_performance",
      method: request.request_method,
      path: request.path,
      status: response.status,
      duration_ms: result.duration_ms,
      sql_query_count: result.sql_query_count,
      request_id: request.request_id
    }.to_json)
  end

  def request_slow_threshold_ms
    ENV.fetch("REQUEST_SLOW_THRESHOLD_MS", 500).to_i
  end

  def render_api_error(message:, status:, code:, details: nil)
    payload = {
      error: message,
      code: code
    }
    payload[:details] = details if details.present?

    render json: payload, status: status
  end
end
