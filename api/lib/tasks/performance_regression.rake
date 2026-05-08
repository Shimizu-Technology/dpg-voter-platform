require "json"

namespace :performance do
  desc "Check latest baseline against guardrail thresholds"
  task :regression_check, [ :report_path ] => :environment do |_task, args|
    ensure_non_production_regression!

    report_path = args[:report_path].presence || ENV["REPORT_PATH"] || default_report_path
    report = load_baseline_report!(report_path)
    failures = evaluate_guardrails(report)

    puts "Performance regression check report: #{report_path}"
    if failures.empty?
      puts "PASS: all performance guardrails met."
      next
    end

    puts "FAIL: regression guardrails violated:"
    failures.each { |failure| puts "  - #{failure}" }
    abort "performance:regression_check failed"
  end

  def default_report_path
    Rails.root.join("..", "docs", "performance", "baseline-latest.json").to_s
  end

  def load_baseline_report!(path)
    raise "Baseline report not found at #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def evaluate_guardrails(report)
    thresholds = default_guardrail_thresholds
    failures = []

    thresholds.each do |scenario_name, limits|
      scenario = report.dig("scenarios", scenario_name)
      unless scenario
        failures << "#{scenario_name}: missing scenario in report"
        next
      end

      p95 = scenario.dig("timing_ms", "p95").to_f
      sql_avg = scenario.dig("sql_queries", "avg").to_f

      if p95 > limits[:p95_max_ms]
        failures << "#{scenario_name}: p95 #{p95}ms exceeds #{limits[:p95_max_ms]}ms"
      end
      if sql_avg > limits[:sql_avg_max]
        failures << "#{scenario_name}: avg SQL #{sql_avg} exceeds #{limits[:sql_avg_max]}"
      end
    end

    failures
  end

  def default_guardrail_thresholds
    {
      "supporters_index_default" => { p95_max_ms: 60, sql_avg_max: 10 },
      "supporters_index_filtered_search" => { p95_max_ms: 90, sql_avg_max: 15 },
      "dashboard_show_payload" => { p95_max_ms: 60, sql_avg_max: 10 },
      "war_room_index_payload" => { p95_max_ms: 80, sql_avg_max: 10 },
      "poll_watcher_index_payload" => { p95_max_ms: 60, sql_avg_max: 10 }
    }
  end

  def ensure_non_production_regression!
    raise "Performance regression check is blocked in production." if Rails.env.production?
  end
end
