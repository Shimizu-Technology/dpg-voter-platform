# Campaign Tracker Seed Data
# Source: GEC Precinct Breakdown as of January 25, 2026

require "digest"

puts "Seeding Campaign Tracker..."

DEFAULT_BOOTSTRAP_ADMIN_EMAILS = [
  "shimizutechnology@gmail.com"
].freeze

DISTRICT_DEFINITIONS = [
  {
    number: 1,
    name: "District 1",
    description: "Lagu 1 & 2",
    villages: [ "Yigo", "Dededo" ]
  },
  {
    number: 2,
    name: "District 2",
    description: "Kattan",
    villages: [ "Tamuning", "Hagåtña", "Agana Heights", "Mongmong/Toto/Maite", "Barrigada" ]
  },
  {
    number: 3,
    name: "District 3",
    description: "Luchan",
    villages: [ "Mangilao", "Yona", "Chalan Pago/Ordot", "Sinajana" ]
  },
  {
    number: 4,
    name: "District 4",
    description: "Haya 1",
    villages: [ "Asan-Ma'ina", "Piti", "Sånta Rita-Sumai", "Hågat" ]
  },
  {
    number: 5,
    name: "District 5",
    description: "Haya 2",
    villages: [ "Humåtak", "Malesso'", "Inalåhan", "Talo'fo'fo'" ]
  }
].freeze

def env_csv(name)
  ENV.fetch(name, "")
    .split(",")
    .map { |value| value.strip.downcase }
    .reject(&:blank?)
end

def env_truthy?(name)
  ActiveModel::Type::Boolean.new.cast(ENV[name])
end

# Campaign
campaign = Campaign.find_or_create_by!(name: CampaignBranding::CAMPAIGN_LABEL) do |c|
  c.election_year = 2026
  c.election_type = "primary"
  c.status = "active"
  c.candidate_names = CampaignBranding::CANDIDATE_NAMES
  c.party = CampaignBranding::PARTY
  c.primary_color = "#1B3A6B"
  c.secondary_color = "#C41E3A"
  c.welcome_sms_template = CampaignBranding::DEFAULT_WELCOME_SMS_TEMPLATE if c.respond_to?(:welcome_sms_template=)
end

puts "  Campaign: #{campaign.name}"

district_lookup = DISTRICT_DEFINITIONS.each_with_object({}) do |definition, memo|
  district = District.find_or_initialize_by(campaign_id: campaign.id, number: definition[:number])
  district.name = definition[:name]
  district.description = definition[:description]
  district.save!

  definition[:villages].each do |village_name|
    memo[village_name] = district
  end
end

puts "  #{District.where(campaign_id: campaign.id).count} campaign districts seeded"

# Villages + Precincts (official GEC data, Jan 25, 2026)
VILLAGE_DATA = [
  {
    name: "Hagåtña", region: "Central", population: 943,
    precincts: [ { number: "1", alpha_range: "A-Z", voters: 344, polling_site: "Guam Congress Building" } ]
  },
  {
    name: "Asan-Ma'ina", region: "Central", population: 2011,
    precincts: [ { number: "2", alpha_range: "A-Z", voters: 859, polling_site: "Asan/Maina Community Center" } ]
  },
  {
    name: "Piti", region: "Central", population: 1585,
    precincts: [ { number: "3", alpha_range: "A-Z", voters: 786, polling_site: "Jose L.G. Rios Middle School Cafeteria" } ]
  },
  {
    name: "Hågat", region: "South", population: 4515,
    precincts: [
      { number: "4", alpha_range: "A-L", voters: 1027, polling_site: "Oceanview Middle School Classrooms" },
      { number: "4A", alpha_range: "M-Z", voters: 918, polling_site: "Oceanview Middle School Classrooms" }
    ]
  },
  {
    name: "Sånta Rita-Sumai", region: "South", population: 6470,
    precincts: [
      { number: "5", alpha_range: "A-K", voters: 847, polling_site: "Harry S. Truman Elem. School" },
      { number: "5A", alpha_range: "L-Z", voters: 965, polling_site: "Harry S. Truman Elem. School" }
    ]
  },
  {
    name: "Humåtak", region: "South", population: 647,
    precincts: [ { number: "6", alpha_range: "A-Z", voters: 428, polling_site: "Humåtak Mayor's Office" } ]
  },
  {
    name: "Malesso'", region: "South", population: 1604,
    precincts: [ { number: "7", alpha_range: "A-Z", voters: 902, polling_site: "Merizo Martyrs Memorial Elem. School" } ]
  },
  {
    name: "Inalåhan", region: "South", population: 2317,
    precincts: [
      { number: "8", alpha_range: "A-Md", voters: 731, polling_site: "Inalahan Middle School" },
      { number: "8A", alpha_range: "Me-Z", voters: 658, polling_site: "Inalahan Middle School" }
    ]
  },
  {
    name: "Talo'fo'fo'", region: "South", population: 3550,
    precincts: [
      { number: "9", alpha_range: "A-M", voters: 893, polling_site: "Talofofo Elem. School" },
      { number: "9A", alpha_range: "N-Z", voters: 743, polling_site: "Talofofo Elem. School" }
    ]
  },
  {
    name: "Yona", region: "South", population: 6298,
    precincts: [
      { number: "10", alpha_range: "A-D", voters: 967, polling_site: "M.U. Lujan Elem. School" },
      { number: "10A", alpha_range: "E-Pd", voters: 905, polling_site: "M.U. Lujan Elem. School" },
      { number: "10B", alpha_range: "Pe-Z", voters: 947, polling_site: "M.U. Lujan Elem. School" }
    ]
  },
  {
    name: "Chalan Pago/Ordot", region: "Central", population: 7064,
    precincts: [
      { number: "11", alpha_range: "A-D", voters: 911, polling_site: "Chalan Pago-Ordot Multipurpose Shelter" },
      { number: "11A", alpha_range: "E-Pd", voters: 864, polling_site: "Chalan Pago-Ordot Multipurpose Shelter" },
      { number: "11B", alpha_range: "Pe-Z", voters: 920, polling_site: "Chalan Pago-Ordot Multipurpose Shelter" }
    ]
  },
  {
    name: "Sinajana", region: "Central", population: 2611,
    precincts: [
      { number: "12", alpha_range: "A-L", voters: 792, polling_site: "C.L. Taitano Elem. School" },
      { number: "12A", alpha_range: "M-Z", voters: 753, polling_site: "C.L. Taitano Elem. School" }
    ]
  },
  {
    name: "Agana Heights", region: "Central", population: 3673,
    precincts: [
      { number: "13", alpha_range: "A-L", voters: 772, polling_site: "Agana Heights Elem. School" },
      { number: "13A", alpha_range: "M-Z", voters: 710, polling_site: "Agana Heights Elem. School" }
    ]
  },
  {
    name: "Mongmong/Toto/Maite", region: "Central", population: 6380,
    precincts: [
      { number: "14", alpha_range: "A-I", voters: 1054, polling_site: "J.Q. San Miguel Elem. School" },
      { number: "14A", alpha_range: "J-Z", voters: 1037, polling_site: "J.Q. San Miguel Elem. School" }
    ]
  },
  {
    name: "Barrigada", region: "Central", population: 7956,
    precincts: [
      { number: "15", alpha_range: "A-Crt", voters: 900, polling_site: "P.C. Lujan Elem. School" },
      { number: "15A", alpha_range: "Cru-K", voters: 894, polling_site: "P.C. Lujan Elem. School" },
      { number: "15B", alpha_range: "L-P", voters: 926, polling_site: "P.C. Lujan Elem. School" },
      { number: "15C", alpha_range: "Q-Z", voters: 974, polling_site: "P.C. Lujan Elem. School" }
    ]
  },
  {
    name: "Mangilao", region: "Central", population: 13476,
    precincts: [
      { number: "16", alpha_range: "A-Cd", voters: 937, polling_site: "George Washington High School" },
      { number: "16A", alpha_range: "Ce-F", voters: 983, polling_site: "George Washington High School" },
      { number: "16B", alpha_range: "G-Mh", voters: 989, polling_site: "George Washington High School" },
      { number: "16C", alpha_range: "Mi-R", voters: 877, polling_site: "George Washington High School" },
      { number: "16D", alpha_range: "S-Z", voters: 976, polling_site: "George Washington High School" }
    ]
  },
  {
    name: "Tamuning", region: "North", population: 18489,
    precincts: [
      { number: "17", alpha_range: "A-Cn", voters: 989, polling_site: "JFK High School" },
      { number: "17A", alpha_range: "Co-H", voters: 975, polling_site: "JFK High School" },
      { number: "17B", alpha_range: "I-Mn", voters: 982, polling_site: "JFK High School" },
      { number: "17C", alpha_range: "Mo-Sal", voters: 991, polling_site: "JFK High School" },
      { number: "17D", alpha_range: "Sam-Z", voters: 998, polling_site: "JFK High School" }
    ]
  },
  {
    name: "Dededo", region: "North", population: 44908,
    precincts: [
      { number: "18", alpha_range: "A-Bar", voters: 1129, polling_site: "Wettengel Elem. School" },
      { number: "18A", alpha_range: "Bas-Caq", voters: 1129, polling_site: "Wettengel Elem. School" },
      { number: "18B", alpha_range: "Car-Cz", voters: 1114, polling_site: "Wettengel Elem. School" },
      { number: "18C", alpha_range: "D", voters: 884, polling_site: "Okkodo High School" },
      { number: "18D", alpha_range: "E-Gar", voters: 927, polling_site: "Okkodo High School" },
      { number: "18E", alpha_range: "Gas-Jd", voters: 909, polling_site: "Okkodo High School" },
      { number: "18F", alpha_range: "Je-L", voters: 900, polling_site: "Okkodo High School" },
      { number: "18G", alpha_range: "M-Mer", voters: 889, polling_site: "Liguan Elem. School" },
      { number: "18H", alpha_range: "Mes-O", voters: 895, polling_site: "Liguan Elem. School" },
      { number: "18I", alpha_range: "P-Quh", voters: 881, polling_site: "Liguan Elem. School" },
      { number: "18J", alpha_range: "Qui-Sal", voters: 1039, polling_site: "Liguan Elem. School" },
      { number: "18K", alpha_range: "Sam-Tak", voters: 1185, polling_site: "Liguan Elem. School" },
      { number: "18L", alpha_range: "Tal-Z", voters: 1218, polling_site: "Liguan Elem. School" }
    ]
  },
  {
    name: "Yigo", region: "North", population: 19339,
    precincts: [
      { number: "19", alpha_range: "A-Cak", voters: 1002, polling_site: "Dominican Catholic School Veritas Hall" },
      { number: "19A", alpha_range: "Cal-D", voters: 1059, polling_site: "Dominican Catholic School Veritas Hall" },
      { number: "19B", alpha_range: "E-K", voters: 1050, polling_site: "Dominican Catholic School Veritas Hall" },
      { number: "19C", alpha_range: "L-M", voters: 906, polling_site: "D.L. Perez Elem. School" },
      { number: "19D", alpha_range: "N-Q", voters: 785, polling_site: "D.L. Perez Elem. School" },
      { number: "19E", alpha_range: "R-Sn", voters: 807, polling_site: "D.L. Perez Elem. School" },
      { number: "19F", alpha_range: "So-Z", voters: 796, polling_site: "D.L. Perez Elem. School" }
    ]
  }
].freeze

total_villages = 0
total_precincts = 0

VILLAGE_DATA.each do |vdata|
  district = district_lookup[vdata[:name]]
  village = Village.find_or_create_by!(name: vdata[:name]) do |v|
    v.region = vdata[:region]
    v.population = vdata[:population]
    v.district = district
  end
  village.update!(region: vdata[:region], population: vdata[:population], district: district)

  vdata[:precincts].each do |pdata|
    Precinct.find_or_create_by!(number: pdata[:number], village: village) do |p|
      p.alpha_range = pdata[:alpha_range]
      p.registered_voters = pdata[:voters]
      p.polling_site = pdata[:polling_site]
    end
    total_precincts += 1
  end

  # Create a default quota (proportional to 10K goal)
  village_voters = vdata[:precincts].sum { |p| p[:voters] }
  target = (village_voters.to_f / 53628 * 10000).round
  Quota.find_or_create_by!(village: village, campaign: campaign, period: "quarterly") do |q|
    q.target_count = target
    q.target_date = Date.new(2026, 7, 31) # Before Aug 1 primary
    q.district = district
  end
  village.quotas.where(campaign: campaign).update_all(district_id: district&.id)

  total_villages += 1
end

puts "  #{total_villages} villages seeded"
puts "  #{total_precincts} precincts seeded"
puts "  #{Quota.count} quotas created"
puts "  Total registered voters: #{Precinct.sum(:registered_voters)}"
puts "  #{Village.where.not(district_id: nil).count} villages assigned to campaign districts"

bootstrap_admin_emails = (DEFAULT_BOOTSTRAP_ADMIN_EMAILS + env_csv("BOOTSTRAP_ADMIN_EMAILS")).uniq
bootstrap_role = ENV.fetch("BOOTSTRAP_ADMIN_ROLE", "campaign_admin")

if bootstrap_admin_emails.any?
  unless User::ROLES.include?(bootstrap_role)
    raise "Invalid BOOTSTRAP_ADMIN_ROLE=#{bootstrap_role.inspect}. Allowed: #{User::ROLES.join(', ')}"
  end

  bootstrap_admin_emails.each do |email|
    placeholder_clerk_id = "seed-#{Digest::SHA256.hexdigest(email).first(24)}"
    default_name = email.split("@").first.tr("._", " ").split.map(&:capitalize).join(" ")

    user = User.find_or_initialize_by(email: email)
    user.clerk_id = placeholder_clerk_id if user.clerk_id.blank?
    user.name = default_name if user.name.blank?
    user.role = bootstrap_role
    user.save!

    puts "  Bootstrap user: #{email} (#{bootstrap_role})"
  end
else
  puts "  No bootstrap admin emails configured; set BOOTSTRAP_ADMIN_EMAILS or edit DEFAULT_BOOTSTRAP_ADMIN_EMAILS"
end

# ============================================================
# Unassigned Village (GMF/Military/Off-Island voters)
# ============================================================
unassigned_village = Village.find_or_create_by!(name: "Unassigned") do |v|
  v.region = "Other"
  v.population = 0
end
puts "  Unassigned village: #{unassigned_village.name}"

# ============================================================
# Campaign Cycle: Guam 2026 General Election
# Guam Primary: August 1, 2026
# Guam General Election: November 3, 2026
# ============================================================
puts "\nSeeding Campaign Cycle..."

cycle = CampaignCycle.find_or_create_by!(name: "Guam 2026 General Election") do |c|
  c.cycle_type = "general"
  c.status = "archived"
  c.start_date = Date.new(2026, 1, 1)
  c.end_date = Date.new(2026, 11, 3)
  c.monthly_quota_target = 6000
  c.carry_forward_data = true
  c.settings = {
    "due_day" => 23,
    "election_date" => "2026-11-03",
    "primary_date" => "2026-08-01",
    "notes" => "Guam General Election. Primary: Aug 1, 2026. General: Nov 3, 2026."
  }
end

cycle.update!(
  cycle_type: "general",
  status: "archived",
  start_date: Date.new(2026, 1, 1),
  end_date: Date.new(2026, 11, 3),
  monthly_quota_target: 6000,
  carry_forward_data: true,
  settings: {
    "due_day" => 23,
    "election_date" => "2026-11-03",
    "primary_date" => "2026-08-01",
    "notes" => "Guam General Election. Primary: Aug 1, 2026. General: Nov 3, 2026."
  }
)

if cycle.quota_periods.empty?
  cycle.generate_periods!
  puts "  Generated #{cycle.quota_periods.count} quota periods"
end

# Primary cycle
primary_cycle = CampaignCycle.find_or_create_by!(name: "Guam 2026 Primary Election") do |c|
  c.cycle_type = "primary"
  c.status = "active"
  c.start_date = Date.new(2026, 1, 1)
  c.end_date = Date.new(2026, 8, 1)
  c.monthly_quota_target = 6000
  c.carry_forward_data = true
  c.settings = {
    "due_day" => 23,
    "election_date" => "2026-08-01",
    "notes" => "Guam Primary Election — August 1, 2026."
  }
end

primary_cycle.update!(
  cycle_type: "primary",
  status: "active",
  start_date: Date.new(2026, 1, 1),
  end_date: Date.new(2026, 8, 1),
  monthly_quota_target: 6000,
  carry_forward_data: true,
  settings: {
    "due_day" => 23,
    "election_date" => "2026-08-01",
    "notes" => "Guam Primary Election — August 1, 2026."
  }
)

if primary_cycle.quota_periods.empty?
  primary_cycle.generate_periods!
end

puts "  Campaign Cycle: #{cycle.name} (#{cycle.start_date} → #{cycle.end_date})"
puts "  Status: #{cycle.status}, Periods: #{cycle.quota_periods.count}"
puts "  Primary Cycle: #{primary_cycle.name} (#{primary_cycle.quota_periods.count} periods)"

# ============================================================
# Fake Supporter Data (~75 supporters for testing)
# Opt-in only: SEED_DEMO_SUPPORTERS=true rails db:seed
# ============================================================
if env_truthy?("SEED_DEMO_SUPPORTERS")
  puts "\nSeeding fake supporters for testing..."

  # Only seed if we don't have test supporters already
  if Supporter.where(source: "bulk_import").count < 50
    # Pick a few villages for variety
    test_villages = Village.where(name: [ "Dededo", "Tamuning", "Yigo", "Mangilao", "Barrigada", "Chalan Pago/Ordot" ])
    fallback_village = Village.find_by(name: "Dededo") || Village.first

    fake_first_names = %w[Maria Jose Juan Ana Carlos Rosa Antonio Elena Miguel Carmen
      Francisco Isabel Luis Paula Roberto Sofia David Clara Jorge Teresa
      Kevin Jennifer Michael Sarah James Jennifer Tina Joshua Patricia].freeze
    fake_last_names = %w[Cruz Santos Reyes Flores Garcia Torres Rodriguez Martinez
      Lopez Hernandez Perez Ramirez Aguon Aflague Camacho Pangelinan
      Guerrero Mendiola Taitano San Nicolas Manibusan Blas Borja].freeze

    fake_phone = -> { "671#{rand(100..999)}#{rand(1000..9999)}" }

    supporters_created = 0

    # 30 HIGH-CONFIDENCE MATCHED supporters (verified, registered voters)
    # These have exact DOB matches in the GEC voter roll
    30.times do
      village = test_villages.sample || fallback_village
      first = fake_first_names.sample
      last = fake_last_names.sample
      dob = Date.new(rand(1950..2000), rand(1..12), rand(1..28))

      s = Supporter.new(
        first_name: first,
        last_name: last,
        village: village,
        source: "bulk_import",
        attribution_method: "staff_manual",
        review_status: "approved",
        public_review_status: "not_applicable",
        status: "active",
        verification_status: "verified",
        registered_voter: true,
        dob: dob,
        contact_number: fake_phone.call,
        opt_in_text: true,
        turnout_status: "not_yet_voted",
        created_at: rand(1..60).days.ago,
        updated_at: rand(1..30).days.ago
      )
      s.save(validate: false)
      supporters_created += 1
    end

    # 25 AMBIGUOUS supporters (unverified, similar DOB/name — for vetting queue)
    25.times do
      village = test_villages.sample || fallback_village
      first = fake_first_names.sample
      last = fake_last_names.sample
      month = rand(1..12)
      day = rand(1..12)
      dob = Date.new(rand(1960..1995), month, day)

      s = Supporter.new(
        first_name: first,
        last_name: last,
        village: village,
        source: "staff_entry",
        attribution_method: "staff_manual",
        review_status: "pending",
        public_review_status: "not_applicable",
        status: "active",
        verification_status: "unverified",
        registered_voter: nil,
        dob: dob,
        contact_number: fake_phone.call,
        opt_in_text: [ true, false ].sample,
        turnout_status: "not_yet_voted",
        created_at: rand(1..30).days.ago,
        updated_at: rand(1..15).days.ago
      )
      s.save(validate: false)
      supporters_created += 1
    end

    # 20 UNMATCHED / FLAGGED supporters (not in GEC roll — testing flagged state)
    20.times do
      village = test_villages.sample || fallback_village
      first = fake_first_names.sample
      last = fake_last_names.sample

      s = Supporter.new(
        first_name: first,
        last_name: last,
        village: village,
        source: "qr_signup",
        attribution_method: "qr_self_signup",
        intake_status: "pending_public_review",
        review_status: "pending",
        public_review_status: "pending",
        status: "active",
        verification_status: "flagged",
        registered_voter: false,
        dob: nil,
        contact_number: fake_phone.call,
        opt_in_text: true,
        turnout_status: "not_yet_voted",
        created_at: rand(1..20).days.ago,
        updated_at: rand(1..10).days.ago
      )
      s.save(validate: false)
      supporters_created += 1
    end

    puts "  Created #{supporters_created} fake supporters"
    puts "    - Verified/matched: 30"
    puts "    - Unverified/ambiguous: 25"
    puts "    - Flagged/unmatched: 20"
  else
    puts "  Fake supporters already exist (#{Supporter.where(source: 'bulk_import').count} bulk_import records)"
  end
else
  puts "\nSkipping fake supporter seed data (set SEED_DEMO_SUPPORTERS=true to enable it)"
end

puts "\nDone!"
