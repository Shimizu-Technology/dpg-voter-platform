# frozen_string_literal: true

# Assign poll_watcher and village_chief users to villages
# so the Poll Watcher strike list and War Room features work in demos.
#
# Run: rails runner db/seeds/demo_poll_watchers.rb

tamuning = Village.find_by(name: "Tamuning")
dededo = Village.find_by(name: "Dededo")

unless tamuning
  puts "ERROR: Tamuning village not found. Run db:seed first."
  exit 1
end

# Assign poll_watcher users to Tamuning (our primary demo village)
poll_watchers = User.where(role: "poll_watcher")
if poll_watchers.any?
  poll_watchers.update_all(assigned_village_id: tamuning.id)
  puts "✓ Assigned #{poll_watchers.count} poll_watcher(s) to #{tamuning.name}"
else
  puts "⚠ No poll_watcher users found"
end

# Assign village_chief users to Tamuning
village_chiefs = User.where(role: "village_chief")
if village_chiefs.any?
  village_chiefs.update_all(assigned_village_id: tamuning.id)
  puts "✓ Assigned #{village_chiefs.count} village_chief(s) to #{tamuning.name}"
else
  puts "⚠ No village_chief users found"
end

# Assign block_leader users to Tamuning
block_leaders = User.where(role: "block_leader")
if block_leaders.any?
  block_leaders.update_all(assigned_village_id: tamuning.id)
  puts "✓ Assigned #{block_leaders.count} block_leader(s) to #{tamuning.name}"
else
  puts "⚠ No block_leader users found"
end

# Assign district_coordinators to Tamuning's district
if dededo
  coordinators = User.where(role: "district_coordinator")
  if coordinators.any?
    coordinators.update_all(assigned_district_id: dededo.district_id)
    puts "✓ Assigned #{coordinators.count} coordinator(s) to district #{dededo.district_id}"
  end
end

# Ensure some supporters in Tamuning have precinct assignments
tamuning_precincts = Precinct.where(village: tamuning)
if tamuning_precincts.any?
  unassigned = Supporter.where(village: tamuning, precinct_id: nil).limit(100)
  if unassigned.any?
    # Distribute evenly across Tamuning precincts
    unassigned.each_with_index do |supporter, i|
      precinct = tamuning_precincts[i % tamuning_precincts.size]
      supporter.update_columns(precinct_id: precinct.id)
    end
    puts "✓ Assigned #{unassigned.count} Tamuning supporters to precincts"
  else
    puts "✓ All Tamuning supporters already have precincts"
  end
else
  puts "⚠ No precincts found for Tamuning"
end

puts "\nPoll watcher demo data ready!"
puts "Poll watchers can now access Tamuning precincts for strike list testing."
