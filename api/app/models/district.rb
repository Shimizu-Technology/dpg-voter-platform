class District < ApplicationRecord
  belongs_to :campaign
  has_many :villages, dependent: :nullify
  has_many :quotas, dependent: :destroy

  belongs_to :coordinator, class_name: "User", optional: true

  validates :name, presence: true
end
