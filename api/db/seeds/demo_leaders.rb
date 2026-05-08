# frozen_string_literal: true

# Demo block leaders with realistic QR code signups
# Run: rails runner db/seeds/demo_leaders.rb

LEADERS = [
  { name: "Pedro Reyes", village: "Tamuning", code: "PERE-TAM-A1B2", signups: 28 },
  { name: "Maria Santos", village: "Dededo", code: "MASA-DED-C3D4", signups: 24 },
  { name: "Frank Aguon", village: "Barrigada", code: "FRAG-BAR-E5F6", signups: 21 },
  { name: "Rosa Taitano", village: "Yigo", code: "ROTA-YIG-G7H8", signups: 18 },
  { name: "Juan Mendiola", village: "Mangilao", code: "JUME-MAN-I9J0", signups: 16 },
  { name: "Carmen Cruz", village: "Sinajana", code: "CACR-SIN-K1L2", signups: 14 },
  { name: "Joseph Blas", village: "Chalan Pago/Ordot", code: "JOBL-CHA-M3N4", signups: 12 },
  { name: "Teresa Flores", village: "Tamuning", code: "TEFL-TAM-O5P6", signups: 11 },
  { name: "Antonio Perez", village: "Dededo", code: "ANPE-DED-Q7R8", signups: 9 },
  { name: "Gloria Muna", village: "Asan-Ma'ina", code: "GLMU-ASA-S9T0", signups: 8 },
  { name: "Ben Toves", village: "Agana Heights", code: "BETO-AGA-U1V2", signups: 7 },
  { name: "Catherine Ada", village: "Mongmong/Toto/Maite", code: "CAAD-MON-W3X4", signups: 5 }
]

LEADERS.each do |leader|
  village = Village.find_by(name: leader[:village])
  next unless village

  # Update existing QR-signup supporters to use this leader code, or create new ones
  existing_qr = Supporter.where(village: village, source: "qr_signup", leader_code: nil).limit(leader[:signups])

  if existing_qr.count >= leader[:signups]
    existing_qr.update_all(leader_code: leader[:code])
    puts "  Updated #{leader[:signups]} supporters with code #{leader[:code]} (#{leader[:name]}, #{leader[:village]})"
  else
    # Update what we have, create the rest
    updated = existing_qr.count
    existing_qr.update_all(leader_code: leader[:code]) if updated > 0

    remaining = leader[:signups] - updated
    # Also grab some staff_entry supporters without codes
    staff = Supporter.where(village: village, leader_code: nil).limit(remaining)
    staff.update_all(leader_code: leader[:code], source: "qr_signup")
    puts "  Set #{updated + staff.count} supporters with code #{leader[:code]} (#{leader[:name]}, #{leader[:village]})"
  end
end

puts "\nLeaderboard ready! #{LEADERS.size} block leaders with #{LEADERS.sum { |l| l[:signups] }} total attributed signups."
