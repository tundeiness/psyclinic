class Appointment < ApplicationRecord
  belongs_to :client_profile
  belongs_to :therapist_profile
  belongs_to :availability_slot

  enum :status, { booked: 0, completed: 1, cancelled: 2 }, default: :booked

  validate :slot_belongs_to_therapist
  validate :slot_is_approved, on: :create
  validate :slot_not_already_booked, on: :create

  scope :upcoming, lambda {
    joins(:availability_slot)
      .where(status: :booked)
      .where("availability_slots.starts_at > ?", Time.current)
  }

  def cancel!
    update!(status: :cancelled)
  end

  private

  def slot_belongs_to_therapist
    return if availability_slot.blank? || therapist_profile_id.blank?

    if availability_slot.therapist_profile_id != therapist_profile_id
      errors.add(:availability_slot, "does not belong to the selected therapist")
    end
  end

  def slot_is_approved
    return if availability_slot.blank?

    errors.add(:availability_slot, "is not available for booking") unless availability_slot.approved?
  end

  def slot_not_already_booked
    return if availability_slot.blank?

    taken = Appointment
      .where(availability_slot_id: availability_slot_id)
      .where.not(status: :cancelled)
      .where.not(id: id)
      .exists?

    errors.add(:availability_slot, "is already booked") if taken
  end
end
