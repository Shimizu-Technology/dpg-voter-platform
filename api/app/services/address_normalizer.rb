# frozen_string_literal: true

class AddressNormalizer
  SUFFIX_ALIASES = {
    "av" => "ave",
    "ave" => "ave",
    "avenue" => "ave",
    "blvd" => "blvd",
    "boulevard" => "blvd",
    "cir" => "cir",
    "circle" => "cir",
    "ct" => "ct",
    "court" => "ct",
    "dr" => "dr",
    "drive" => "dr",
    "hwy" => "hwy",
    "highway" => "hwy",
    "ln" => "ln",
    "lane" => "ln",
    "pl" => "pl",
    "place" => "pl",
    "rd" => "rd",
    "road" => "rd",
    "rt" => "rt",
    "route" => "rt",
    "st" => "st",
    "street" => "st",
    "ter" => "ter",
    "terrace" => "ter",
    "wy" => "way",
    "way" => "way"
  }.freeze

  TRAILING_LOCALITIES = [
    "agana heights",
    "barrigada heights",
    "maina",
    "hagatna",
    "hagatna heights",
    "santa rita",
    "sinajana",
    "tamuning",
    "tumon"
  ].freeze

  class << self
    def canonical_key(address, village_name: nil)
      canonical = canonical_address(address, village_name: village_name)
      return nil if canonical.blank?

      village = canonical_village(village_name)
      [ village, canonical ].compact_blank.join("|")
    end

    def canonical_address(address, village_name: nil)
      tokens = normalize_tokens(address)
      tokens = collapse_po_box(tokens)
      tokens = strip_trailing_localities(tokens, village_name)
      tokens.join(" ").presence
    end

    private

    def normalize_tokens(value)
      value.to_s
        .downcase
        .gsub(/[^\p{Alnum}]+/, " ")
        .squish
        .split
        .map { |token| SUFFIX_ALIASES.fetch(token, token) }
    end

    def collapse_po_box(tokens)
      collapsed = []
      index = 0

      while index < tokens.length
        if tokens[index] == "p" && tokens[index + 1] == "o" && tokens[index + 2] == "box"
          collapsed << "po" << "box"
          index += 3
        elsif tokens[index] == "post" && tokens[index + 1] == "office" && tokens[index + 2] == "box"
          collapsed << "po" << "box"
          index += 3
        else
          collapsed << tokens[index]
          index += 1
        end
      end

      collapsed
    end

    def strip_trailing_localities(tokens, village_name)
      locality_tokens = TRAILING_LOCALITIES.map { |name| normalize_tokens(name) }
      locality_tokens << normalize_tokens(village_name) if village_name.present?

      loop do
        original = tokens
        locality_tokens.each do |candidate|
          next if candidate.blank? || tokens.length <= candidate.length

          tokens = tokens[0...-candidate.length] if tokens.last(candidate.length) == candidate
        end
        break if tokens == original
      end

      tokens
    end

    def canonical_village(village_name)
      normalize_tokens(village_name).join(" ").presence
    end
  end
end
