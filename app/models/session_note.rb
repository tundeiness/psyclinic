class SessionNote < ApplicationRecord
  include Signable

  belongs_to :appointment
  belongs_to :client_profile
  belongs_to :author, class_name: "User"

  validates :appointment_id,
    uniqueness: { message: "already has a session note" }
end
