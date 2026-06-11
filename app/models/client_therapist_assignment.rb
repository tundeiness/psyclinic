class ClientTherapistAssignment < ApplicationRecord
  belongs_to :client_profile
  belongs_to :from_therapist, class_name: "TherapistProfile", optional: true
  belongs_to :to_therapist,   class_name: "TherapistProfile"
  belongs_to :forfeited_block,
    class_name: "SessionBlock", optional: true

  validates :started_at, presence: true

  scope :open,   -> { where(ended_at: nil) }
  scope :closed, -> { where.not(ended_at: nil) }

  # True for the assignment that is currently in effect — i.e. not
  # yet closed by a subsequent switch.
  def open?
    ended_at.nil?
  end
end
