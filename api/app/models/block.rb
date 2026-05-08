class Block < ApplicationRecord
  belongs_to :village
  has_many :supporters, dependent: :nullify
  belongs_to :leader, class_name: "User", optional: true

  validates :name, presence: true
end
