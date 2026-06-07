class ServicePlanNote < ApplicationRecord
  include Signable

  belongs_to :client_profile
  belongs_to :appointment, optional: true
  belongs_to :author, class_name: "User"

  # One service plan per client — it's a one-off document written at
  # the second session.
  validates :client_profile_id,
    uniqueness: { message: "already has a service plan note" }
end
