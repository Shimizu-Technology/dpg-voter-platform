# frozen_string_literal: true

namespace :campaign do
  desc "Create the 2026 Primary Election campaign cycle with monthly periods"
  task setup_2026_primary: :environment do
    cycle = CampaignCycle.find_or_create_by!(name: "2026 Primary Election") do |c|
      c.cycle_type = "primary"
      c.start_date = Date.new(2026, 1, 1)
      c.end_date = Date.new(2026, 8, 29) # Guam primary election day
      c.monthly_quota_target = 6000
      c.carry_forward_data = true
      c.settings = { "due_day" => 23 }
    end

    # Generate periods with default village targets
    # Targets can be adjusted later via the UI or API
    village_targets = {}
    Village.find_each do |v|
      # Default: distribute 6000 proportionally across villages
      # These are placeholders — Rose will set real targets
      village_targets[v.id] = 200
    end

    cycle.generate_periods!(village_targets: village_targets)

    puts "✅ Campaign cycle created: #{cycle.name}"
    puts "   #{cycle.quota_periods.count} monthly periods generated"
    puts "   #{village_targets.size} villages with default targets"
    puts ""
    puts "   To adjust targets, use the admin UI or:"
    puts "   rails runner \"VillageQuota.where(village_id: X).update_all(target: Y)\""
  end
end
