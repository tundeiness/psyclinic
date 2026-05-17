class User < ApplicationRecord
  devise :database_authenticatable,
    :registerable,
    :recoverable,
    :validatable,
    :jwt_authenticatable,
    jwt_revocation_strategy: JwtDenylist

  enum :role, { client: 0, therapist: 1, admin: 2 }, default: :client

  has_one :therapist_profile, dependent: :destroy
  has_one :client_profile, dependent: :destroy

  validates :first_name, :last_name, presence: true
  validates :role, presence: true

  # Guard against privilege escalation through the public signup endpoint.
  # Admins are seeded or promoted by an existing admin, never self-assigned.
  attr_accessor :allow_admin_assignment

  validate :admin_role_not_self_assigned, on: :create

  after_create :build_role_profile

  def full_name
    "#{first_name} #{last_name}".strip
  end

  # devise-jwt calls this to embed claims; we keep it minimal.
  def jwt_payload
    { "role" => role }
  end

  private

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
