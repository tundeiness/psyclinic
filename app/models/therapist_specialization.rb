class TherapistSpecialization < ApplicationRecord
  belongs_to :therapist_profile
  belongs_to :specialization

  validates :specialization_id,
    uniqueness: { scope: :therapist_profile_id }
end
