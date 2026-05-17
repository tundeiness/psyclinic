class TherapistProfile < ApplicationRecord
  belongs_to :user

  has_many :availability_slots, dependent: :destroy
  has_many :appointments, dependent: :destroy

  has_many :therapist_specializations, dependent: :destroy
  has_many :specializations, through: :therapist_specializations

  scope :active, -> { where(active: true) }

  delegate :full_name, :email, to: :user

  # Clients who have at least one (non-cancelled) appointment with this
  # therapist. Replaces the old admin-assigned pairing.
  def clients_with_appointments
    ClientProfile
      .joins(:appointments)
      .where(appointments: { therapist_profile_id: id })
      .where.not(appointments: { status: :cancelled })
      .distinct
  end
end
