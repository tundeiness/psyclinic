class Specialization < ApplicationRecord
  has_many :therapist_specializations, dependent: :destroy
  has_many :therapist_profiles, through: :therapist_specializations

  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
