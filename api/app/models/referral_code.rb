class ReferralCode < ApplicationRecord
  belongs_to :assigned_user, class_name: "User", optional: true
  belongs_to :created_by_user, class_name: "User", optional: true
  belongs_to :village

  has_many :supporters, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :display_name, presence: true

  scope :active, -> { where(active: true) }

  def self.generate_unique_code(display_name:, village_name:)
    base_prefix = build_prefix(display_name)
    base_suffix = village_name.to_s.first(3).upcase

    # Generate candidates in batches and check existence in one query
    candidates = Array.new(20) { "#{base_prefix}-#{base_suffix}-#{SecureRandom.hex(2).upcase}" }
    existing = where(code: candidates).pluck(:code).to_set
    candidates.each { |c| return c unless existing.include?(c) }

    # Longer codes as fallback
    candidates = Array.new(50) { "#{base_prefix}-#{base_suffix}-#{SecureRandom.hex(4).upcase}" }
    existing = where(code: candidates).pluck(:code).to_set
    candidates.each { |c| return c unless existing.include?(c) }

    raise "Unable to generate unique referral code after 70 attempts (prefix: #{base_prefix}, suffix: #{base_suffix})"
  end

  def self.build_prefix(display_name)
    tokens = display_name.to_s.strip.split(/\s+/).reject(&:blank?)
    return "LEAD" if tokens.empty?

    prefix = tokens.map { |token| token.gsub(/[^A-Za-z0-9]/, "").first(2).to_s.upcase }.join
    prefix = prefix.first(8)
    prefix.present? ? prefix : "LEAD"
  end
  private_class_method :build_prefix
end
