# frozen_string_literal: true

namespace :supporters do
  desc "Backfill missing source attribution on supporters (dry-run by default)"
  task backfill_source: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    puts dry_run ? "=== DRY RUN (set DRY_RUN=false to apply) ===" : "=== APPLYING CHANGES ==="

    null_source = Supporter.where(source: nil)
    puts "Supporters with NULL source: #{null_source.count}"

    if null_source.count.zero?
      puts "Nothing to backfill!"
      next
    end

    with_leader_code = null_source.where.not(leader_code: [ nil, "" ])
    without_leader_code = null_source.where(leader_code: [ nil, "" ])

    puts "  → With leader_code (→ qr_signup): #{with_leader_code.count}"
    puts "  → Without leader_code (→ staff_entry): #{without_leader_code.count}"

    unless dry_run
      # Using update_all intentionally — bypasses callbacks/validations for bulk efficiency.
      # Model validation now allows nil source (allow_nil: true) so legacy records
      # can be re-saved without error even before backfill runs.
      updated_qr = with_leader_code.update_all(source: "qr_signup")
      updated_staff = without_leader_code.update_all(source: "staff_entry")
      puts "\nApplied:"
      puts "  #{updated_qr} supporters → qr_signup"
      puts "  #{updated_staff} supporters → staff_entry"
    end

    puts "\nFinal distribution:"
    Supporter.group(:source).count.sort_by { |_, v| -v }.each do |source, count|
      puts "  #{source || 'NULL'}: #{count}"
    end
  end
end
