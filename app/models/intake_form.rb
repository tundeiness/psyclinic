class IntakeForm < ApplicationRecord
  include Signable

  belongs_to :client_profile
  belongs_to :author, class_name: "User"

  validates :client_profile_id,
    uniqueness: { message: "already has an intake form" }

  # JSONB shapes (informational; not enforced at DB level):
  #
  # medications: [
  #   { "drug" => str, "dosage" => str, "started" => str,
  #     "ends" => str, "medical_condition" => str }, ...
  # ]
  #
  # history: [
  #   { "period" => str, "career_academic_event" => str,
  #     "social_details" => str }, ...
  # ]
  #
  # family_tree: [
  #   { "relation" => str, "relationship_progression" => str,
  #     "current_state" => str }, ...
  # ]
  #
  # substance_use: [
  #   { "substance" => str, "frequency_mode" => str,
  #     "onset_progression" => str }, ...
  # ]
end
