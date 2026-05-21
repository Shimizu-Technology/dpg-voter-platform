# frozen_string_literal: true

class QuotaPeriod < ApplicationRecord
  STATUSES = %w[open closed archived].freeze

  belongs_to :campaign_cycle
  has_many :supporters, dependent: :nullify
  has_many :village_quotas, dependent: :destroy

  validates :name, :start_date, :end_date, :due_date, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :quota_target, numericality: { greater_than_or_equal_to: 0 }
  validate :end_date_on_or_after_start_date
  validate :due_date_on_or_after_start_date
  validate :single_open_period, if: :open?

  scope :ordered, -> { order(start_date: :desc, id: :desc) }
  scope :open, -> { where(status: "open") }
  scope :visible, -> { where.not(status: "archived") }
  scope :covering, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }

  def self.active_for(date = Date.current)
    open.covering(date).order(start_date: :desc, id: :desc).first || open.order(start_date: :desc, id: :desc).first
  end

  def open?
    status == "open"
  end

  def close!
    update!(status: "closed")
  end

  def activate!
    transaction do
      self.class.where.not(id: id).open.update_all(status: "closed", updated_at: Time.current)
      update!(status: "open")
    end
  end

  def archive!
    if open?
      errors.add(:status, "cannot archive an active period; close or activate another period first")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(status: "archived")
  end

  private

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be on or after the start date") if end_date < start_date
  end

  def due_date_on_or_after_start_date
    return if start_date.blank? || due_date.blank?

    errors.add(:due_date, "must be on or after the start date") if due_date < start_date
  end

  def single_open_period
    scope = self.class.open
    scope = scope.where.not(id: id) if persisted?
    errors.add(:status, "can only be open for one period at a time") if scope.exists?
  end
end
