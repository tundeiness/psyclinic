class ClientProfile < ApplicationRecord
  belongs_to :user

  has_many :appointments, dependent: :destroy
  # Therapist-private notes about this client. Association exists only so
  # notes are cleaned up if the client is removed; never serialized to
  # the client.
  has_many :client_notes, dependent: :destroy

  delegate :full_name, :email, to: :user
end
