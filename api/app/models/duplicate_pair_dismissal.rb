class DuplicatePairDismissal < ApplicationRecord
  belongs_to :supporter
  belongs_to :dismissed_supporter, class_name: "Supporter"
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :supporter_id, presence: true
  validates :dismissed_supporter_id, presence: true
  validates :supporter_id, uniqueness: { scope: :dismissed_supporter_id }
  validate :ordered_pair

  def self.dismissed?(left_id, right_id)
    first_id, second_id = ordered_pair(left_id, right_id)
    exists?(supporter_id: first_id, dismissed_supporter_id: second_id)
  end

  def self.create_for_pair!(left_id, right_id, resolved_by: nil, note: nil)
    first_id, second_id = ordered_pair(left_id, right_id)
    find_or_create_by!(supporter_id: first_id, dismissed_supporter_id: second_id) do |dismissal|
      dismissal.resolved_by = resolved_by
      dismissal.note = note
    end
  end

  def self.match_ids_for(supporter_id, candidate_ids)
    ids = Array(candidate_ids).compact.uniq
    return [] if supporter_id.blank? || ids.empty?

    where(supporter_id: supporter_id, dismissed_supporter_id: ids)
      .or(where(supporter_id: ids, dismissed_supporter_id: supporter_id))
      .pluck(:supporter_id, :dismissed_supporter_id)
      .flatten
      .uniq
      .excluding(supporter_id)
  end

  def self.ordered_pair(left_id, right_id)
    ids = [ left_id, right_id ].map(&:to_i).sort
    raise ArgumentError, "duplicate dismissal requires two different supporters" if ids.first == ids.second

    ids
  end

  private_class_method :ordered_pair

  private

  def ordered_pair
    return if supporter_id.blank? || dismissed_supporter_id.blank?
    return if supporter_id < dismissed_supporter_id

    errors.add(:supporter_id, "must be less than dismissed supporter id")
  end
end
