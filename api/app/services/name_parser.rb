class NameParser
  SUFFIXES = %w[JR SR II III IV V].freeze

  class << self
    def split_supporter_name(full_name)
      name = full_name.to_s.strip
      return blank_result if name.blank?

      if name.include?(",")
        last_part, given_part = name.split(",", 2).map(&:strip)
        first_name, middle_name = split_given_names(given_part)
        return {
          first_name: first_name,
          middle_name: middle_name,
          last_name: last_part,
          uncertain: false
        }
      end

      if name =~ /\s*&\s*/
        parts = name.split(/\s*&\s*/, 2)
        first_person = parts[0].to_s.strip
        second_part = parts[1].to_s.strip.split(/\s+/)

        if second_part.size >= 2
          first_name, middle_name = split_given_names(second_part[0..-2].join(" "))
          return {
            first_name: first_name,
            middle_name: middle_name,
            last_name: second_part[-1],
            uncertain: true,
            couple_note: "Couple entry — only importing \"#{[ first_name, middle_name, second_part[-1] ].compact_blank.join(' ')}\". \"#{first_person}\" may need separate entry."
          }
        end

        return {
          first_name: second_part[0] || first_person,
          middle_name: nil,
          last_name: "",
          uncertain: true,
          couple_note: "Couple entry — \"#{first_person} & #{second_part[0]}\". Last name missing. \"#{first_person}\" may need separate entry."
        }
      end

      parenthetical_suffix = name[/\s*(\([^)]+\))\z/, 1]
      sanitized_name = name.sub(/\s*\([^)]+\)\z/, "").strip
      words = sanitized_name.split(/\s+/)

      compact_suffix = split_compact_initial_last(words.last)
      compact_split = compact_suffix.present?
      if compact_suffix
        words[-1, 1] = [ compact_suffix[:middle_name], compact_suffix[:last_name] ]
      end

      parsed = case words.size
      when 0
        blank_result
      when 1
        { first_name: words[0], middle_name: nil, last_name: "", uncertain: true }
      when 2
        { first_name: words[0], middle_name: nil, last_name: words[1], uncertain: false }
      else
        if suffix_token?(words.last)
          {
            first_name: words[0],
            middle_name: words[1...-2].join(" ").presence,
            last_name: [ words[-2], words[-1] ].join(" "),
            uncertain: false
          }
        else
          {
          first_name: words[0],
          middle_name: words[1...-1].join(" ").presence,
          last_name: words[-1],
          uncertain: words.size > 3
        }
        end
      end

      if parenthetical_suffix.present? && parsed[:last_name].present?
        parsed[:last_name] = "#{parsed[:last_name]} #{parenthetical_suffix}"
        parsed[:uncertain] = true
      end

      parsed[:uncertain] = true if compact_split

      parsed
    end

    def split_print_name(print_name)
      split_supporter_name(print_name)
    end

    def split_gec_name(full_name)
      name = full_name.to_s.strip
      return blank_result if name.blank?

      if name.include?(",")
        last_part, given_part = name.split(",", 2).map(&:strip)
        first_name, middle_name = split_given_names(given_part)
        return {
          first_name: first_name,
          middle_name: middle_name,
          last_name: last_part
        }
      end

      split_supporter_name(name).slice(:first_name, :middle_name, :last_name)
    end

    def combine(first_name:, middle_name: nil, last_name: nil, format: :display)
      given_names = [ first_name, middle_name ].compact_blank.join(" ")

      case format
      when :last_comma_first
        if last_name.present? && given_names.present?
          "#{last_name}, #{given_names}"
        else
          [ last_name, given_names ].compact_blank.join(" ")
        end
      else
        [ first_name, middle_name, last_name ].compact_blank.join(" ")
      end
    end

    private

    def split_given_names(given_names)
      words = given_names.to_s.strip.split(/\s+/)
      return [ "", nil ] if words.empty?

      [ words[0], words[1..].join(" ").presence ]
    end

    def blank_result
      { first_name: "", middle_name: nil, last_name: "", uncertain: true }
    end

    def suffix_token?(word)
      SUFFIXES.include?(word.to_s.upcase.delete("."))
    end

    def split_compact_initial_last(word)
      token = word.to_s.strip
      return nil if token.blank?

      match = token.match(/\A((?:[A-Z]\.){1,})([A-Z][A-Za-z'’-]+)\z/)
      return nil unless match

      {
        middle_name: match[1],
        last_name: match[2]
      }
    end
  end
end
