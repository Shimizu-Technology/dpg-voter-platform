# frozen_string_literal: true

class GecImport < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze
  IMPORT_TYPES = %w[full_list changes_only].freeze

  belongs_to :uploaded_by_user, class_name: "User", optional: true
  belongs_to :activated_for_election_by_user, class_name: "User", optional: true
  has_one :upload_payload, class_name: "GecImportUpload", dependent: :destroy
  has_many :change_records, class_name: "GecImportChange", dependent: :destroy
  has_many :skipped_rows, class_name: "GecImportSkippedRow", dependent: :destroy

  validates :gec_list_date, presence: true
  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :import_type, inclusion: { in: IMPORT_TYPES }

  scope :latest, -> { order(created_at: :desc, id: :desc) }
  scope :completed, -> { where(status: "completed") }
  scope :active_election_day, -> { completed.where(active_election_day: true) }

  def self.active_election_day_import
    active_election_day.latest.first
  end

  def activate_for_election!(actor_user:)
    raise ActiveRecord::RecordInvalid, self unless status == "completed"

    transaction do
      self.class.where.not(id: id).update_all(active_election_day: false)
      update!(
        active_election_day: true,
        activated_for_election_at: Time.current,
        activated_for_election_by_user: actor_user
      )
    end
  end

  def raw_source_available?
    raw_file_s3_key.present?
  end

  def import_artifact_available?
    original_file_s3_key.present?
  end

  def downloadable_file_available?
    raw_source_available? || import_artifact_available?
  end

  def imported_from_pdf?
    metadata.is_a?(Hash) && metadata["pdf_qa"].present?
  end

  def raw_source_filename
    raw_filename.presence
  end

  def downloadable_file_key
    raw_file_s3_key.presence || original_file_s3_key.presence
  end

  def downloadable_filename
    raw_filename.presence || original_filename.presence || filename
  end

  def downloadable_content_type
    raw_content_type.presence || original_content_type.presence
  end

  def change_summary
    {
      total_records: total_records,
      new_records: new_records,
      updated_records: updated_records,
      removed_records: removed_records,
      transferred_records: transferred_records,
      ambiguous_dob_count: ambiguous_dob_count,
      re_vetted_count: re_vetted_count,
      import_type: import_type
    }
  end
end
