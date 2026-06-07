class ClientProfile < ApplicationRecord
  belongs_to :user

  has_many :appointments, dependent: :destroy
  # Therapist-private notes about this client. Association exists only so
  # notes are cleaned up if the client is removed; never serialized to
  # the client.
  # EMR associations replace the old free-form ClientNote.
  has_one  :intake_form,         dependent: :destroy
  has_one  :service_plan_note,   dependent: :destroy
  has_many :session_notes,       dependent: :destroy
  has_many :dass_assessments,    dependent: :destroy
  has_many :wheel_of_life_assessments, dependent: :destroy


  delegate :full_name, :email, to: :user
end
