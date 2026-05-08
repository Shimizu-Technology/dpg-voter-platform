class AuditLog < ApplicationRecord
  belongs_to :auditable, polymorphic: true
  belongs_to :actor_user, class_name: "User", optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
