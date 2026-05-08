require "bigdecimal"

namespace :data do
  FIRST_NAMES = %w[
    Juan Maria Pedro Ana Jose Carmen Francisco Rosa Antonio Elena
    Miguel Isabel Roberto Teresa Carlos Dolores Luis Gloria Ramon Luz
    Fernando Rosario Eduardo Victoria Manuel Esperanza Ricardo Pilar
    Frank John Mary James Robert Patricia David Jennifer Michael Linda
    Chris Jessica Daniel Sarah Thomas Karen Mark Lisa Paul Betty
  ].freeze

  LAST_NAMES = %w[
    Cruz Santos Reyes Blas Taitano Flores Perez Aguon Manibusan Duenas
    Leon_Guerrero Quinata Unpingco Camacho Charfauros Lizama Quitugua
    Bamba Borja Mesa Toves Ada Chargualaf Sablan Lujan Mendiola Paulino
    Castro Pangelinan Torres Rosario Salas San_Nicolas Villagomez Acosta
  ].freeze

  STREET_NAMES = [
    "Marine Corps Dr", "Pale San Vitores Rd", "Route 1", "Route 4",
    "Route 8", "Route 10", "Route 16", "Chalan San Antonio",
    "Aspinall Ave", "Farenholt Ave", "Army Dr", "Cross Island Rd",
    "Tun Jesus Crisostomo St", "Chalan Pago Main St", "Ysengsong Rd", "Dairy Rd"
  ].freeze

  PRESET_SIZES = [ 5_000, 10_000, 30_000 ].freeze
  DEFAULT_SEED = 20_260_213

  desc "Generate synthetic supporter datasets (5k/10k/30k presets). Usage: rails \"data:seed_synthetic_supporters[5000]\" RESET=true"
  task :seed_synthetic_supporters, [ :size ] => :environment do |_task, args|
    ensure_non_production!

    size = (args[:size] || ENV["SIZE"] || PRESET_SIZES.first).to_i
    unless PRESET_SIZES.include?(size)
      raise ArgumentError, "Invalid size #{size.inspect}. Allowed sizes: #{PRESET_SIZES.join(', ')}"
    end

    seed_value = (ENV["SEED"] || DEFAULT_SEED).to_i
    reset = ActiveModel::Type::Boolean.new.cast(ENV.fetch("RESET", "false"))
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))
    batch_size = (ENV["BATCH_SIZE"] || 1_000).to_i

    villages = Village.includes(:precincts).order(:id).to_a
    raise "No villages found. Run db:seed first." if villages.empty?

    if reset
      puts "Removing previous synthetic supporters (leader_code prefix SYNTH-)..."
      deleted = Supporter.where("leader_code LIKE ?", "SYNTH-%").delete_all
      puts "Deleted #{deleted} rows."
    end

    distribution = distribute_counts_by_voter_weight(villages, total_size: size)
    total_to_create = distribution.sum { |entry| entry[:count] }

    puts "Starting synthetic seed"
    puts "  dataset size: #{total_to_create}"
    puts "  random seed: #{seed_value}"
    puts "  dry run: #{dry_run}"
    puts "  batch size: #{batch_size}"

    srand(seed_value)

    if dry_run
      distribution.each do |entry|
        puts "  #{entry[:village].name}: #{entry[:count]}"
      end
      puts "Dry run complete. No records inserted."
      next
    end

    generated = 0
    records = []
    now = Time.current

    distribution.each do |entry|
      village = entry[:village]
      precincts = village.precincts.to_a

      entry[:count].times do |index_in_village|
        precinct = precincts.sample
        created_at = now - rand(0..180).days - rand(0..86_399).seconds

        records << {
          print_name: synthetic_name(village_name: village.name, index_in_village: index_in_village),
          contact_number: synthetic_phone,
          dob: synthetic_dob,
          email: nil,
          street_address: synthetic_address,
          village_id: village.id,
          precinct_id: precinct&.id,
          block_id: nil,
          entered_by_user_id: nil,
          referred_from_village_id: nil,
          source: "bulk_import",
          status: "active",
          registered_voter: rand < 0.85,
          yard_sign: rand < 0.35,
          motorcade_available: rand < 0.28,
          leader_code: "SYNTH-#{generated + 1}",
          created_at: created_at,
          updated_at: created_at
        }

        generated += 1
        if records.length >= batch_size
          Supporter.insert_all!(records)
          records.clear
        end
      end
    end

    Supporter.insert_all!(records) if records.any?

    puts "Synthetic seed complete."
    puts "  inserted: #{generated}"
    puts "  active supporters total: #{Supporter.active.count}"
  end

  desc "Generate synthetic poll watcher reports for today. Usage: rails \"data:seed_synthetic_poll_reports[8]\" RESET_TODAY=true"
  task :seed_synthetic_poll_reports, [ :reports_per_precinct ] => :environment do |_task, args|
    ensure_non_production!

    reports_per_precinct = (args[:reports_per_precinct] || ENV["REPORTS_PER_PRECINCT"] || 8).to_i
    raise ArgumentError, "reports_per_precinct must be > 0" if reports_per_precinct <= 0

    reset_today = ActiveModel::Type::Boolean.new.cast(ENV.fetch("RESET_TODAY", "false"))
    seed_value = (ENV["SEED"] || DEFAULT_SEED).to_i
    srand(seed_value)

    if reset_today
      deleted = PollReport.where("reported_at >= ?", Time.current.beginning_of_day).delete_all
      puts "Deleted #{deleted} existing reports from today."
    end

    precincts = Precinct.order(:id).to_a
    raise "No precincts found. Run db:seed first." if precincts.empty?

    report_types = %w[turnout_update turnout_update turnout_update line_length issue closing]
    created = 0
    now = Time.current

    precincts.each do |precinct|
      registered = [ precinct.registered_voters.to_i, 1 ].max
      last_count = 0

      reports_per_precinct.times do |idx|
        remaining = [ registered - last_count, 0 ].max
        increment = if idx == reports_per_precinct - 1
          [ remaining, rand(0..[ registered / 12, 1 ].max) ].min
        else
          rand(0..[ registered / 10, 1 ].max)
        end
        voter_count = [ last_count + increment, registered ].min
        last_count = voter_count

        offset_seconds = rand(0..57_600) # spread across last ~16 hours
        reported_at = now.beginning_of_day + offset_seconds.seconds + idx.seconds

        PollReport.create!(
          precinct: precinct,
          user: nil,
          voter_count: voter_count,
          report_type: report_types.sample,
          notes: nil,
          reported_at: [ reported_at, now ].min
        )
        created += 1
      end
    end

    puts "Synthetic poll reports complete."
    puts "  precincts: #{precincts.size}"
    puts "  reports per precinct: #{reports_per_precinct}"
    puts "  inserted: #{created}"
    puts "  today poll reports total: #{PollReport.where('reported_at >= ?', Time.current.beginning_of_day).count}"
  end

  def ensure_non_production!
    raise "Synthetic seeding is blocked in production." if Rails.env.production?
  end

  def distribute_counts_by_voter_weight(villages, total_size:)
    total_voters = villages.sum { |v| [ v.registered_voters.to_i, 1 ].max }

    rows = villages.map do |village|
      weight = [ village.registered_voters.to_i, 1 ].max
      exact = BigDecimal(weight * total_size) / BigDecimal(total_voters)
      floor = exact.floor
      {
        village: village,
        count: floor,
        remainder: (exact - floor).to_f
      }
    end

    assigned = rows.sum { |row| row[:count] }
    remaining = total_size - assigned
    rows.sort_by { |row| -row[:remainder] }.first(remaining).each { |row| row[:count] += 1 }
    rows
  end

  def synthetic_name(village_name:, index_in_village:)
    "#{FIRST_NAMES.sample} #{LAST_NAMES.sample.tr('_', ' ')} #{village_name[0, 2].upcase}#{index_in_village}"
  end

  def synthetic_phone
    "671-#{rand(200..999)}-#{rand(1000..9999)}"
  end

  def synthetic_dob
    Date.new(rand(1948..2006), rand(1..12), rand(1..28))
  end

  def synthetic_address
    "#{rand(100..9999)} #{STREET_NAMES.sample}"
  end
end
