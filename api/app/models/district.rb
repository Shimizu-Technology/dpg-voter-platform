class District < ApplicationRecord
  belongs_to :campaign
  has_many :villages, dependent: :nullify

  belongs_to :coordinator, class_name: "User", optional: true

  validates :name, presence: true
end
