class Appointment < ApplicationRecord
  belongs_to :client_profile
  belongs_to :therapist_profile
  belongs_to :availability_slot
  belongs_to :session_block, optional: true

  # Integers preserved so existing rows keep their meaning. New states
  # appended. pending_payment/booked/completed reserve the slot;
  # cancelled/payment_failed release it (see partial unique index).
  enum :status, {
    booked: 0,
    completed: 1,
    cancelled: 2,
    pending_payment: 3,
    payment_failed: 4
  }, default: :pending_payment

  # v2 distinction. Default :normal so any existing rows / future
  # callers that don't set this explicitly behave like the legacy
  # model. Assessment sessions are individually paid; normal sessions
  # draw from a SessionBlock.
  enum :session_kind, { normal: 0, assessment: 1 }, default: :normal

  has_one :payment, dependent: :destroy

  RESERVING_STATUSES = %w[booked completed pending_payment].freeze

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
      .where(status: RESERVING_STATUSES)
      .where.not(id: id)
      .exists?

    errors.add(:availability_slot, "is already booked") if taken
  end
end
