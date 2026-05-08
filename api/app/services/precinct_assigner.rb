# frozen_string_literal: true

# Automatically assigns a supporter to the correct precinct based on their
# last name and village, using the GEC alpha_range data stored on precincts.
#
# Examples of alpha_range formats:
#   "A-Z"   — full alphabet (single precinct villages)
#   "A-L"   — simple letter split
#   "A-Md"  — two-char upper bound (names A through Md*)
#   "Me-Z"  — two-char lower bound
#   "E-Pd"  — two-char upper bound
#   "Pe-Z"  — two-char lower bound
class PrecinctAssigner
  # Returns the matching Precinct record (or nil).
  def self.assign(supporter)
    return nil if supporter.village_id.blank?

    precincts = Precinct.where(village_id: supporter.village_id).order(:number).to_a
    return nil if precincts.empty?
    return precincts.first if precincts.one?

    # If no last name, we can't determine alpha range — leave unassigned
    return nil if supporter.last_name.blank?

    find_matching_precinct(supporter.last_name.strip, precincts)
  end

  # Returns just the precinct_id (convenience wrapper).
  def self.assign_id(supporter)
    assign(supporter)&.id
  end

  class << self
    private

    def find_matching_precinct(last_name, precincts)
      precincts.each do |precinct|
        next if precinct.alpha_range.blank?
        return precinct if in_alpha_range?(last_name, precinct.alpha_range)
      end

      # Fallback: if no range matched (shouldn't happen with valid GEC data),
      # assign to the last precinct in the village.
      precincts.last
    end

    def in_alpha_range?(name, range)
      parts = range.split("-", 2).map(&:strip)
      return false unless parts.length == 2

      range_start = parts[0].downcase
      range_end   = parts[1].downcase
      name_lower  = name.strip.downcase

      # For the start bound: compare using the length of range_start.
      # "E-Pd" means names whose first char >= "e".
      # "Pe-Z" means names whose first 2 chars >= "pe".
      start_prefix = name_lower[0, range_start.length]

      # For the end bound: compare using the length of range_end.
      # "A-Md" means names whose first 2 chars <= "md".
      # "A-L" means names whose first char <= "l".
      end_prefix = name_lower[0, range_end.length]

      start_prefix >= range_start && end_prefix <= range_end
    end
  end
end
