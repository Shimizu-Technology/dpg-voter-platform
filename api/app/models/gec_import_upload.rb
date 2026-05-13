# frozen_string_literal: true

class GecImportUpload < ApplicationRecord
  belongs_to :gec_import

  validates :filename, presence: true
  validate :stored_upload_present

  private

  def stored_upload_present
    return if file_data.present? || file_s3_key.present?

    errors.add(:base, "Upload payload must include file data or an S3 key")
  end
end
