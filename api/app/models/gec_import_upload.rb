# frozen_string_literal: true

class GecImportUpload < ApplicationRecord
  belongs_to :gec_import

  validates :filename, presence: true
  validates :file_data, presence: true
end
