require "json"
require "fileutils"

namespace :performance do
  desc "Capture backend baseline timings. Usage: rails \"performance:capture_baseline[5000]\""
  task :capture_baseline, [ :dataset_size ] => :environment do |_task, args|
    ensure_non_production!

    dataset_size = (args[:dataset_size] || ENV["DATASET_SIZE"] || 5_000).to_i
    iterations = (ENV["ITERATIONS"] || 7).to_i
    warmup_runs = (ENV["WARMUP_RUNS"] || 1).to_i

    puts "Capturing baseline (dataset_size=#{dataset_size}, iterations=#{iterations}, warmup=#{warmup_runs})..."
    report = run_baseline(dataset_size: dataset_size, iterations: iterations, warmup_runs: warmup_runs)
    path = write_report(report)
    puts "Baseline report written: #{path}"
  end

  def run_baseline(dataset_size:, iterations:, warmup_runs:)
    scenarios = {
      "supporters_index_default" => lambda {
        supporters = Supporter.includes(:village, :precinct, :block).order(created_at: :desc).limit(50).to_a
        supporters.map do |s|
          [ s.id, s.print_name, s.contact_number, s.village&.name, s.precinct&.number, s.created_at ]
        end
      },
      "supporters_index_filtered_search" => lambda {
        sample = Supporter.order(created_at: :desc).select(:print_name, :village_id).first
        query = sample&.print_name.to_s.downcase[0, 3]
        scope = Supporter.includes(:village, :precinct, :block)
        scope = scope.where(village_id: sample.village_id) if sample&.village_id.present?
        if query.present?
          q = "%#{query}%"
          scope = scope.where(
            "LOWER(print_name) LIKE :q OR regexp_replace(contact_number, '\\D', '', 'g') LIKE :q",
            q: q
          )
        end
        scope.order(created_at: :desc).limit(50).to_a.each { |s| s.village&.name; s.precinct&.number }
      },
      "dashboard_show_payload" => lambda {
        campaign = Campaign.active.first
        village_ids = Village.pluck(:id)
        supporter_counts = Supporter.active.where(village_id: village_ids).group(:village_id).count
        today_counts = Supporter.active.today.where(village_id: village_ids).group(:village_id).count
        week_counts = Supporter.active.this_week.where(village_id: village_ids).group(:village_id).count
        quota_targets = campaign ? Quota.where(campaign_id: campaign.id, village_id: village_ids).group(:village_id).sum(:target_count) : {}
        Village.order(:name).map do |village|
          supporter_count = supporter_counts[village.id] || 0
          target = quota_targets[village.id] || 0
          {
            id: village.id,
            supporter_count: supporter_count,
            today_count: today_counts[village.id] || 0,
            week_count: week_counts[village.id] || 0,
            quota_target: target,
            quota_percentage: target.positive? ? (supporter_count * 100.0 / target).round(1) : 0
          }
        end
      },
      "war_room_index_payload" => lambda {
        latest_reports = PollReport.today.latest_per_precinct.index_by(&:precinct_id)
        all_reports_today = PollReport.today.chronological.includes(precinct: :village).limit(20).to_a
        precinct_rows = Precinct.select(:id, :village_id, :registered_voters)
        precinct_ids_by_village = Hash.new { |hash, key| hash[key] = [] }
        registered_voters_by_village = Hash.new(0)
        precinct_rows.each do |precinct|
          precinct_ids_by_village[precinct.village_id] << precinct.id
          registered_voters_by_village[precinct.village_id] += precinct.registered_voters.to_i
        end
        supporter_counts_by_village = Supporter.active.group(:village_id).count
        villages = Village.order(:name).map do |village|
          precinct_ids = precinct_ids_by_village[village.id]
          village_reports = latest_reports.values_at(*precinct_ids).compact
          total_registered = registered_voters_by_village[village.id]
          total_voted = village_reports.sum(&:voter_count)
          {
            id: village.id,
            turnout_pct: total_registered > 0 ? (total_voted * 100.0 / total_registered).round(1) : 0,
            supporter_count: supporter_counts_by_village[village.id] || 0,
            issue_flag: village_reports.any? { |r| r.report_type == "issue" }
          }
        end
        [ villages.size, all_reports_today.size ]
      },
      "poll_watcher_index_payload" => lambda {
        accessible_precincts = Precinct.includes(:village).order(:number)
        latest_reports = PollReport.today.latest_per_precinct.where(precinct_id: accessible_precincts.select(:id)).index_by(&:precinct_id)
        villages = accessible_precincts.group_by(&:village).map do |village, village_precincts|
          precincts = village_precincts.map do |p|
            report = latest_reports[p.id]
            {
              id: p.id,
              reporting: report.present?,
              turnout_pct: report && p.registered_voters.to_i > 0 ? (report.voter_count * 100.0 / p.registered_voters).round(1) : nil
            }
          end
          {
            id: village.id,
            precinct_count: precincts.size,
            reporting_count: precincts.count { |x| x[:reporting] }
          }
        end
        villages.size
      }
    }

    benchmark_results = scenarios.transform_values do |runner|
      measure_scenario(iterations: iterations, warmup_runs: warmup_runs) { runner.call }
    end

    {
      captured_at: Time.current.iso8601,
      environment: Rails.env,
      dataset_hint_size: dataset_size,
      totals: {
        supporters_active_count: Supporter.active.count,
        supporters_total_count: Supporter.count,
        villages_count: Village.count,
        precincts_count: Precinct.count,
        poll_reports_today_count: PollReport.today.count
      },
      scenarios: benchmark_results
    }
  end

  def measure_scenario(iterations:, warmup_runs:)
    warmup_runs.times { yield }

    elapsed_ms = []
    sql_counts = []
    iterations.times do
      query_count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]

        query_count += 1
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      elapsed_ms << ((finish - start) * 1000.0).round(2)
      sql_counts << query_count
    end

    sorted_times = elapsed_ms.sort
    {
      runs: iterations,
      timing_ms: {
        p50: percentile(sorted_times, 50),
        p95: percentile(sorted_times, 95),
        avg: (elapsed_ms.sum / elapsed_ms.size).round(2),
        min: sorted_times.first,
        max: sorted_times.last
      },
      sql_queries: {
        avg: (sql_counts.sum.to_f / sql_counts.size).round(2),
        min: sql_counts.min,
        max: sql_counts.max
      }
    }
  end

  def percentile(sorted_values, pct)
    return 0 if sorted_values.empty?

    rank = ((pct / 100.0) * (sorted_values.length - 1)).round
    sorted_values[rank]
  end

  def write_report(report)
    docs_dir = Rails.root.join("..", "docs", "performance")
    FileUtils.mkdir_p(docs_dir)
    timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
    file_path = docs_dir.join("baseline-#{timestamp}.json")
    File.write(file_path, JSON.pretty_generate(report))

    latest_path = docs_dir.join("baseline-latest.json")
    File.write(latest_path, JSON.pretty_generate(report))
    file_path.to_s
  end

  def ensure_non_production!
    raise "Performance baseline task is blocked in production." if Rails.env.production?
  end
end
