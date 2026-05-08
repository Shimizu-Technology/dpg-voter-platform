namespace :districts do
  desc "Sync district definitions and village assignments"
  task sync: :environment do
    definitions = [
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
    ]

    aliases = {
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
    }

    campaign = Campaign.find_by(status: "active") || Campaign.order(:id).last
    abort "No campaign found. Seed campaigns first." unless campaign

    puts "Syncing districts for campaign ##{campaign.id} (#{campaign.name})..."

    district_records = definitions.each_with_object({}) do |definition, memo|
      district = District.where(campaign_id: campaign.id, number: definition[:number]).first ||
        District.where(campaign_id: campaign.id, name: definition[:name]).first ||
        District.new(campaign_id: campaign.id)
      district.number = definition[:number]
      district.name = definition[:name]
      district.description = definition[:description]
      district.save!
      memo[definition[:number]] = district
      puts "  Upserted #{district.name}"
    end

    unresolved = []
    assignments = 0

    definitions.each do |definition|
      district = district_records.fetch(definition[:number])
      definition[:villages].each do |raw_name|
        normalized = raw_name.to_s.strip.downcase
        canonical = aliases.fetch(normalized, raw_name)
        village = Village.find_by(name: canonical)
        unless village
          unresolved << raw_name
          next
        end

        village.update!(district_id: district.id)
        assignments += 1
      end
    end

    if unresolved.any?
      warn "WARNING: Unresolved villages: #{unresolved.uniq.sort.join(', ')}"
      warn "These villages were skipped. Create them and re-run this task to complete assignment."
    end

    puts "  Assigned #{assignments} village-to-district links"
    puts "Done."
  end
end
