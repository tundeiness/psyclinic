# A clinical note written by a therapist about a client they have seen.
# Therapist-private: there is no client-facing endpoint or serializer
# that exposes these. A therapist may only create/read notes for a
# client who has booked an appointment with them (enforced in Ability
# and the controller).
class ClientNote < ApplicationRecord
  belongs_to :therapist_profile
  belongs_to :client_profile

  validates :body, presence: true, length: { maximum: 10_000 }

  scope :recent, -> { order(created_at: :desc) }
end
