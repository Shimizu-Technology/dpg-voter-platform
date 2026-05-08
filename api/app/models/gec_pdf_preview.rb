# frozen_string_literal: true

class GecPdfPreview < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  RETENTION_WINDOW = 1.day
  NON_TERMINAL_RETENTION_WINDOW = 1.hour

  belongs_to :uploaded_by_user, class_name: "User"

  validates :preview_request_id, presence: true, uniqueness: true
  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :source_present_on_create, on: :create

  scope :stale, lambda {
    where(status: %w[completed failed]).where("updated_at < ?", RETENTION_WINDOW.ago)
      .or(where(status: %w[pending processing]).where("updated_at < ?", NON_TERMINAL_RETENTION_WINDOW.ago))
  }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def queued?
    %w[pending processing].include?(status)
  end

  def self.purge_stale!
    stale.select(:id, :file_s3_key).find_in_batches(batch_size: 100) do |batch|
      ids_to_delete = []
      batch.each do |preview|
        if preview.file_s3_key.present?
          begin
            deleted = S3Service.delete(preview.file_s3_key)
            next unless deleted
          rescue StandardError => e
            Rails.logger.warn("[GecPdfPreview] S3 delete failed for key #{preview.file_s3_key}: #{e.message}")
            next
          end
        end
        ids_to_delete << preview.id
      end
      where(id: ids_to_delete).delete_all if ids_to_delete.any?
    end
  end

  private

  def source_present_on_create
    return if file_data.present? || file_s3_key.present?

    errors.add(:base, "Preview source data must be attached")
  end
end
