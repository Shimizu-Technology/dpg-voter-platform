# Demo Seed Data — Realistic supporters for Saturday demo
# Run: rails runner db/seeds/demo_supporters.rb

FIRST_NAMES = %w[
  Juan Maria Pedro Ana Jose Carmen Francisco Rosa Antonio Elena
  Miguel Isabel Roberto Teresa Carlos Dolores Luis Gloria Ramon Luz
  Fernando Rosario Eduardo Victoria Manuel Esperanza Ricardo Pilar
  Frank John Mary James Robert Patricia David Jennifer Michael Linda
  Chris Jessica Daniel Sarah Thomas Karen Mark Lisa Paul Betty
  Vincent Catherine Peter Joann Philip Grace Albert Frances George Helen
  Tony Bernadette Jesse Priscilla Ray Josephine Ben Margaret Felix Lucia
  Danny Theresa Leonard Christine Edward Cecilia Ronald Lorraine
  Jerome Annette Eugene Rosemary Arnold Catherine Rudy Jeanette
].freeze

LAST_NAMES = %w[
  Cruz Santos Reyes Blas Taitano Flores Perez Aguon Manibusan Duenas
  Leon Guerrero Quinata Unpingco Camacho Charfauros Lizama Quitugua
  Bamba Borja Mesa Toves Ada Chargualaf Sablan Lujan Mendiola Paulino
  Castro Pangelinan Torres Rosario Salas San Nicolas Villagomez Acosta
  Babauta Bautista Benavente Cepeda Concepcion De Leon Diaz Eay
  Fejeran Garrido Gumataotao Iglesias Mantanona Muna Natividad
  Palomo Rivera Roberto San Agustin Sanchez Siguenza Sudo Tenorio
  Terlaje Topasna Tudela Untalan Villaverde Yamashita
].freeze

STREETS = [
  "Marine Corps Dr", "Pale San Vitores Rd", "Route 1", "Route 4",
  "Route 8", "Route 10", "Route 16", "Chalan San Antonio",
  "Aspinall Ave", "O'Brien Dr", "Farenholt Ave", "Army Dr",
  "Harmon Loop Rd", "Cross Island Rd", "Tun Jesus Crisostomo St",
  "Gov. Carlos Camacho Rd", "Chalan Pago Main St", "Ysengsong Rd",
  "Dairy Rd", "University Dr", "Liguan Terrace", "Swamp Rd",
  "Santa Monica Ave", "Perino St", "Espiritu St", "Luna Ave"
].freeze

def random_phone
  "671-#{rand(200..999)}-#{rand(1000..9999)}"
end

def random_address
  "#{rand(100..9999)} #{STREETS.sample}"
end

def random_name
  "#{FIRST_NAMES.sample} #{LAST_NAMES.sample}"
end

def random_email(name)
  clean = name.downcase.gsub(/[^a-z ]/, "").split(" ").join(".")
  "#{clean}#{rand(1..99)}@#{%w[gmail.com yahoo.com hotmail.com outlook.com].sample}"
end

puts "Seeding demo supporters..."

villages = Village.all.index_by(&:name)

# Distribution: Tamuning gets the most (primary demo village)
# Other villages get varying amounts to make dashboard interesting
VILLAGE_DISTRIBUTION = {
  "Tamuning" => 185,
  "Dededo" => 120,
  "Yigo" => 85,
  "Barrigada" => 65,
  "Mangilao" => 55,
  "Chalan Pago/Ordot" => 45,
  "Sinajana" => 40,
  "Mongmong/Toto/Maite" => 35,
  "Agana Heights" => 30,
  "Yona" => 25,
  "Talo'fo'fo'" => 20,
  "Inalåhan" => 18,
  "Hågat" => 15,
  "Sånta Rita-Sumai" => 12,
  "Asan-Ma'ina" => 10,
  "Piti" => 8,
  "Malesso'" => 8,
  "Humåtak" => 5,
  "Hagåtña" => 4
}.freeze

total_created = 0

VILLAGE_DISTRIBUTION.each do |village_name, count|
  village = villages[village_name]
  unless village
    puts "  WARNING: Village '#{village_name}' not found, skipping"
    next
  end

  precincts = village.precincts.to_a
  created = 0

  count.times do
    first = FIRST_NAMES.sample
    last = LAST_NAMES.sample
    name = "#{first} #{last}"
    # Skip if duplicate name in same village
    next if Supporter.where(village: village).where("LOWER(first_name) = ? AND LOWER(last_name) = ?", first.downcase, last.downcase).exists?

    precinct = precincts.sample if precincts.any?

    # Randomize attributes for realism
    registered = rand < 0.82 # ~82% registered
    yard_sign = rand < 0.35
    motorcade = rand < 0.25
    has_email = rand < 0.6
    has_dob = rand < 0.4
    source = rand < 0.7 ? "staff_entry" : "qr_signup"

    # Spread creation dates over past 2 weeks for realistic "growth"
    days_ago = rand(0..13)
    created_at = days_ago.days.ago + rand(0..86400).seconds

    supporter = Supporter.new(
      first_name: first,
      last_name: last,
      contact_number: random_phone,
      email: has_email ? random_email(name) : nil,
      dob: has_dob ? Date.new(rand(1950..2005), rand(1..12), rand(1..28)) : nil,
      street_address: random_address,
      village: village,
      precinct: precinct,
      registered_voter: registered,
      yard_sign: yard_sign,
      motorcade_available: motorcade,
      opt_in_email: rand < 0.65,
      opt_in_text: rand < 0.75,
      verification_status: rand < 0.6 ? "verified" : (rand < 0.9 ? "unverified" : "flagged"),
      source: source,
      status: "active",
      leader_code: source == "qr_signup" ? "DEMO#{rand(100..999)}" : nil,
    )

    if supporter.save
      # Backdate for realistic growth curve
      supporter.update_columns(created_at: created_at, updated_at: created_at)
      created += 1
    end
  end

  total_created += created
  pct = village.quotas.first&.target_count.to_i > 0 ?
    (created * 100.0 / village.quotas.first.target_count).round(1) : 0
  puts "  #{village_name}: #{created} supporters (#{pct}% of quota)"
end

puts "\nTotal created: #{total_created}"
puts "Grand total: #{Supporter.active.count}"
puts "\nVillage breakdown:"
Village.order(:name).each do |v|
  quota = v.quotas.first&.target_count || 0
  count = v.supporters.active.count
  pct = quota > 0 ? (count * 100.0 / quota).round(1) : 0
  bar = "█" * (pct / 5).to_i
  puts "  #{v.name.ljust(25)} #{count.to_s.rjust(4)} / #{quota.to_s.rjust(4)} (#{pct}%) #{bar}"
end
