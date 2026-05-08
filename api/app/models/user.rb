class User < ApplicationRecord
  ROLES = %w[campaign_admin data_team district_coordinator village_chief block_leader poll_watcher].freeze
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  has_many :entered_supporters, class_name: "Supporter", foreign_key: :entered_by_user_id, dependent: :nullify
  has_many :turnout_updated_supporters, class_name: "Supporter", foreign_key: :turnout_updated_by_user_id, dependent: :nullify
  has_many :supporter_contact_attempts, foreign_key: :recorded_by_user_id, dependent: :restrict_with_exception
  has_many :poll_watcher_precinct_assignments, dependent: :destroy
  has_many :assigned_poll_watcher_precincts, through: :poll_watcher_precinct_assignments, source: :precinct
  has_many :assigned_referral_codes, class_name: "ReferralCode", foreign_key: :assigned_user_id, dependent: :nullify
  has_many :created_referral_codes, class_name: "ReferralCode", foreign_key: :created_by_user_id, dependent: :nullify

  validates :clerk_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
  validates :email, format: { with: EMAIL_FORMAT }
  validates :role, inclusion: { in: ROLES }

  scope :admins, -> { where(role: "campaign_admin") }
  scope :coordinators, -> { where(role: "district_coordinator") }
  scope :chiefs, -> { where(role: "village_chief") }
  scope :leaders, -> { where(role: "block_leader") }

  def admin?
    role == "campaign_admin"
  end

  def coordinator?
    role == "district_coordinator"
  end

  def chief?
    role == "village_chief"
  end

  def leader?
    role == "block_leader"
  end

  def data_team?
    role == "data_team"
  end

  def poll_watcher?
    role == "poll_watcher"
  end

  def can_manage_users?
    admin? || coordinator?
  end
end
