# frozen_string_literal: true

class GecImportChange < ApplicationRecord
  CHANGE_TYPES = %w[new updated removed transferred].freeze

  belongs_to :gec_import

  validates :change_type, inclusion: { in: CHANGE_TYPES }

  scope :latest_first, -> { order(id: :desc) }
end
