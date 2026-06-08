class ClientProfile < ApplicationRecord
  belongs_to :user
  # The therapist this client is currently seeing for normal sessions.
  # Null until the client books their first assessment. Reset on
  # therapist-switch. Set / cleared by the booking + switch flows
  # (later phases).
  belongs_to :current_therapist,
    class_name: "TherapistProfile",
    optional: true

  has_many :appointments, dependent: :destroy

  # v2: blocks of 6 normal sessions purchased by the client for use
  # with their current therapist. Multiple blocks can exist over time
  # (active + completed + forfeited history).
  has_many :session_blocks, dependent: :destroy

  # EMR associations.
  #
  # `intake_forms` is has_many (not has_one) because each therapist who
  # treats this client creates their own intake record for their
  # relationship. Use `intake_form_for(therapist_or_user)` for the
  # specific record.
  has_many :intake_forms, dependent: :destroy
  has_one  :service_plan_note,   dependent: :destroy
  has_many :session_notes,       dependent: :destroy
  has_many :dass_assessments,    dependent: :destroy
  has_many :wheel_of_life_assessments, dependent: :destroy

  delegate :full_name, :email, to: :user

  # Returns the intake form authored by the given therapist (or that
  # therapist's user), or nil if none exists yet for this relationship.
  # Accepts a User or a TherapistProfile for convenience.
  def intake_form_for(therapist)
    user_id = therapist.is_a?(User) ? therapist.id : therapist.user_id
    intake_forms.find_by(author_id: user_id)
  end
end
