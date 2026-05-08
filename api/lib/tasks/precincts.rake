# frozen_string_literal: true

require "csv"

namespace :ct do
  namespace :precincts do
    desc "Sync precinct polling_site from CSV (dry-run by default). Usage: CSV_PATH=path DRY_RUN=true bundle exec rake ct:precincts:sync_polling_sites"
    task sync_polling_sites: :environment do
      csv_path = ENV["CSV_PATH"].to_s.strip
      raise "CSV_PATH is required" if csv_path.empty?
      raise "CSV file not found: #{csv_path}" unless File.exist?(csv_path)

      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
      change_note = ENV["CHANGE_NOTE"].to_s.strip
      actor_email = ENV["ACTOR_EMAIL"].to_s.strip
      actor_user = actor_email.present? ? User.find_by(email: actor_email) : nil

      villages_by_key = Village.all.index_by { |v| normalize_key(v.name) }

      stats = {
        total_rows: 0,
        changed: 0,
        unchanged: 0,
        missing_village: 0,
        missing_precinct: 0,
        invalid: 0
      }

      changes = []

      CSV.foreach(csv_path, headers: true).with_index(2) do |row, line_no|
        stats[:total_rows] += 1

        village_name = field(row, "village", "village_name", "municipality")
        precinct_number = field(row, "precinct_number", "precinct", "number")
        new_polling_site = field(row, "polling_site", "site", "new_polling_site")

        if village_name.blank? || precinct_number.blank? || new_polling_site.blank?
          stats[:invalid] += 1
          puts "[invalid] line #{line_no}: village/precinct_number/polling_site required"
          next
        end

        village = villages_by_key[normalize_key(village_name)]
        unless village
          stats[:missing_village] += 1
          puts "[missing_village] line #{line_no}: #{village_name}"
          next
        end

        precinct = Precinct.where(village_id: village.id)
          .where("LOWER(number) = ?", precinct_number.downcase.strip)
          .first

        unless precinct
          stats[:missing_precinct] += 1
          puts "[missing_precinct] line #{line_no}: #{village.name} / #{precinct_number}"
          next
        end

        old_site = precinct.polling_site.to_s.strip
        new_site = new_polling_site.strip

        if old_site == new_site
          stats[:unchanged] += 1
          next
        end

        changes << {
          line_no: line_no,
          precinct_id: precinct.id,
          village: village.name,
          number: precinct.number,
          from: old_site,
          to: new_site
        }
      end

      stats[:changed] = changes.size

      puts "\n=== Precinct Polling Site Sync Summary ==="
      puts "CSV: #{csv_path}"
      puts "Mode: #{dry_run ? 'DRY_RUN' : 'APPLY'}"
      puts "Rows: #{stats[:total_rows]}"
      puts "Changed: #{stats[:changed]}"
      puts "Unchanged: #{stats[:unchanged]}"
      puts "Missing villages: #{stats[:missing_village]}"
      puts "Missing precincts: #{stats[:missing_precinct]}"
      puts "Invalid rows: #{stats[:invalid]}"

      if changes.any?
        puts "\nSample changes (up to 30):"
        changes.first(30).each do |c|
          puts "- [#{c[:precinct_id]}] #{c[:village]} P#{c[:number]}: '#{c[:from]}' -> '#{c[:to]}'"
        end
      end

      if dry_run
        puts "\nDry run complete. Re-run with DRY_RUN=false to apply."
        next
      end

      applied = 0
      ActiveRecord::Base.transaction do
        changes.each do |c|
          precinct = Precinct.find(c[:precinct_id])
          precinct.update!(polling_site: c[:to])
          applied += 1

          AuditLog.create!(
            auditable: precinct,
            actor_user: actor_user,
            action: "updated",
            changed_data: {
              polling_site: { from: c[:from], to: c[:to] }
            },
            metadata: {
              resource: "precinct",
              source: "csv_sync",
              change_note: change_note.presence || "GEC polling-site refresh",
              import_file: File.basename(csv_path)
            }
          )
        end
      end

      puts "\nApplied #{applied} polling site updates."
      puts "Audit actor: #{actor_user&.email || 'system(nil)'}"
    end

    def field(row, *names)
      names.each do |name|
        return row[name] if row.headers.include?(name)
      end
      nil
    end

    def normalize_key(value)
      value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, " ").squeeze(" ")
    end
  end
end
