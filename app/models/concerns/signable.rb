module Signable
  extend ActiveSupport::Concern

  included do
    # belongs_to :signed_by is added per-model since the foreign key
    # name varies (always `signed_by_id`, but we keep it explicit).
    belongs_to :signed_by, class_name: "User", optional: true

    # Once signed, the record becomes read-only. Attempts to update
    # raise so the controller can return 422 with a helpful message.
    before_update :prevent_post_signing_edits
  end

  def signed?
    signed_at.present?
  end

  def sign!(user)
    raise "Already signed" if signed?
    update!(signed_at: Time.current, signed_by: user)
  end

  private

  def prevent_post_signing_edits
    # Allow the very update that performs the signing itself.
    return if signed_at_changed? && signed_at_was.nil?

    if signed_at_was.present?
      errors.add(:base, "This record is signed and cannot be edited")
      throw(:abort)
    end
  end
end
