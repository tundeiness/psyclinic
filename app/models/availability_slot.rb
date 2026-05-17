class AvailabilitySlot < ApplicationRecord
  belongs_to :therapist_profile

  has_one :appointment, dependent: :restrict_with_error

  enum :status, { proposed: 0, approved: 1, rejected: 2 }, default: :proposed

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts
  validate :no_overlap_for_therapist
  validate :not_in_past, on: :create

  scope :bookable, lambda {
    approved
      .where("starts_at > ?", Time.current)
      .where.missing(:appointment)
  }
  scope :for_therapist, ->(tp_id) { where(therapist_profile_id: tp_id) }

  def booked?
    appointment.present? && !appointment.cancelled?
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end

  def not_in_past
    return if starts_at.blank?

    errors.add(:starts_at, "cannot be in the past") if starts_at < Time.current
  end

  def no_overlap_for_therapist
    return if starts_at.blank? || ends_at.blank? || therapist_profile_id.blank?

    overlapping = AvailabilitySlot
      .where(therapist_profile_id: therapist_profile_id)
      .where.not(id: id)
      .where.not(status: :rejected)
      .where("starts_at < ? AND ends_at > ?", ends_at, starts_at)

    errors.add(:base, "overlaps an existing slot for this therapist") if overlapping.exists?
  end
end
