class SeedDistrictsFromOrgChart < ActiveRecord::Migration[8.1]
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

  VILLAGE_ALIASES = {
    "hagatna" => "Hagåtña",
    "agana hts" => "Agana Heights",
    "agana heights" => "Agana Heights",
    "mtm" => "Mongmong/Toto/Maite",
    "asan/maina" => "Asan-Ma'ina",
    "santa rita" => "Sånta Rita-Sumai",
    "hagat" => "Hågat",
    "talofofo" => "Talo'fo'fo'",
    "humatak" => "Humåtak",
    "inalahan" => "Inalåhan",
    "merizo" => "Malesso'"
  }.freeze

  def up
    campaign = Campaign.find_by(status: "active") || Campaign.order(:id).last
    raise "Cannot seed districts: no campaign found" unless campaign

    district_records = DISTRICT_DEFINITIONS.each_with_object({}) do |definition, memo|
      district = District.find_or_initialize_by(campaign_id: campaign.id, number: definition[:number])
      district.name = definition[:name]
      district.description = definition[:description]
      district.save!
      memo[definition[:number]] = district
    end

    unresolved = []
    assigned_village_ids = []

    DISTRICT_DEFINITIONS.each do |definition|
      district = district_records.fetch(definition[:number])
      definition[:villages].each do |raw_village_name|
        canonical = canonical_village_name(raw_village_name)
        village = Village.find_by(name: canonical)
        unless village
          unresolved << raw_village_name
          next
        end

        village.update!(district_id: district.id)
        assigned_village_ids << village.id
      end
    end

    if unresolved.any?
      say "WARNING: unresolved village names during district seeding: #{unresolved.uniq.sort.join(', ')}"
      say "These villages were skipped. Run `rails db:seed` after creating them to complete assignment."
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "District chart seed should not be automatically rolled back"
  end

  private

  def canonical_village_name(name)
    normalized = name.to_s.strip.downcase
    VILLAGE_ALIASES.fetch(normalized, name)
  end
end
