class User < ApplicationRecord
  devise :database_authenticatable,
    :registerable,
    :recoverable,
    :validatable,
    :jwt_authenticatable,
    jwt_revocation_strategy: JwtDenylist

  enum :role, { client: 0, therapist: 1, admin: 2 }, default: :client

  # Account approval workflow. Clients/therapists self-signup as :pending
  # and cannot log in until an admin approves them. Admins are :approved.
  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  has_one :therapist_profile, dependent: :destroy
  has_one :client_profile, dependent: :destroy
  has_many :notifications, dependent: :destroy

  has_one_attached :avatar
  has_many_attached :documents

  validates :first_name, :last_name, presence: true
  validates :role, presence: true

  # Guard against privilege escalation through the public signup endpoint.
  # Admins are seeded or promoted by an existing admin, never self-assigned.
  attr_accessor :allow_admin_assignment

  validate :admin_role_not_self_assigned, on: :create

  before_validation :set_initial_status, on: :create
  after_create :build_role_profile

  def full_name
    "#{first_name} #{last_name}".strip
  end

  # A therapist whom the admin has promoted to co-admin. Co-admins keep
  # their therapist role but gain admin-like management powers (see
  # Ability). They can never remove the admin or manage co-admins.
  def co_admin?
    therapist? && therapist_profile&.co_admin == true
  end

  # Devise hook: block login until the account is approved. Returning
  # false during authentication yields an :inactive failure.
  def active_for_authentication?
    super && (admin? || approved?)
  end

  def inactive_message
    return :rejected if rejected?
    return :pending_approval unless approved? || admin?

    super
  end

  # devise-jwt embeds these claims.
  def jwt_payload
    { "role" => role, "status" => status }
  end

  private

  def set_initial_status
    # Admins (seeded or promoted by an admin) are immediately approved.
    self.status = :approved if admin?
  end

  def admin_role_not_self_assigned
    return unless role == "admin"
    return if allow_admin_assignment

    errors.add(:role, "cannot be self-assigned")
  end

  def build_role_profile
    case role
    when "therapist"
      create_therapist_profile! unless therapist_profile
    when "client"
      create_client_profile! unless client_profile
    end
  end
end
