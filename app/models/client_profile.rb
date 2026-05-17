class ClientProfile < ApplicationRecord
  belongs_to :user
  belongs_to :therapist_profile, optional: true

  has_many :appointments, dependent: :destroy

  delegate :full_name, :email, to: :user

  def paired?
    therapist_profile_id.present?
  end
end
