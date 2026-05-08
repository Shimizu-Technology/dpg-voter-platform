# frozen_string_literal: true

class GecImportSkippedRow < ApplicationRecord
  RESOLUTION_STATUSES = %w[pending resolved_created resolved_updated dismissed].freeze
  RESOLUTION_ACTIONS = %w[create update dismiss].freeze

  belongs_to :gec_import
  belongs_to :resolved_by_user, class_name: "User", optional: true
  belongs_to :resolved_gec_voter, class_name: "GecVoter", optional: true

  validates :message, presence: true
  validates :row_number, presence: true
  validates :resolution_status, inclusion: { in: RESOLUTION_STATUSES }
  validates :resolution_action, inclusion: { in: RESOLUTION_ACTIONS }, allow_nil: true

  scope :latest_first, -> { order(row_number: :desc, id: :desc) }
end
