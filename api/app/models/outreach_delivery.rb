# frozen_string_literal: true

class OutreachDelivery < ApplicationRecord
  CHANNELS = %w[sms email].freeze
  PROVIDERS = %w[clicksend resend].freeze
  STATUSES = %w[queued sent delivered delivery_delayed failed bounced undelivered suppressed complained unknown].freeze
  RESENDABLE_STATUSES = %w[failed bounced undelivered suppressed delivery_delayed unknown].freeze

  belongs_to :sms_blast, optional: true
  belongs_to :email_blast, optional: true
  belongs_to :supporter
  belongs_to :resend_of, class_name: "OutreachDelivery", optional: true
  has_many :resends, class_name: "OutreachDelivery", foreign_key: :resend_of_id, dependent: :nullify, inverse_of: :resend_of

  validates :channel, inclusion: { in: CHANNELS }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :recipient, presence: true
  validate :belongs_to_exactly_one_blast

  scope :resendable, -> { where(status: RESENDABLE_STATUSES) }
  scope :not_already_resent, -> { where.missing(:resends) }
  scope :recent_first, -> { order(created_at: :desc) }

  def resendable?
    RESENDABLE_STATUSES.include?(status)
  end

  def mark_provider_event!(status:, occurred_at: Time.current, provider_status_code: nil, provider_status_text: nil, provider_error_code: nil, metadata: {})
    attrs = {
      status: status,
      last_event_at: occurred_at,
      provider_status_code: provider_status_code.presence || self.provider_status_code,
      provider_status_text: provider_status_text.presence || self.provider_status_text,
      provider_error_code: provider_error_code.presence || self.provider_error_code,
      metadata: self.metadata.merge(metadata.compact)
    }
    attrs[:delivered_at] = occurred_at if status == "delivered"
    attrs[:failed_at] = occurred_at if %w[failed bounced undelivered suppressed complained].include?(status)
    update!(attrs)
  end

  private

  def belongs_to_exactly_one_blast
    return if sms_blast_id.present? ^ email_blast_id.present?

    errors.add(:base, "must belong to exactly one blast")
  end
end
