class AvailabilitySlotSerializer
  def self.call(slot)
    {
      id: slot.id,
      therapist_profile_id: slot.therapist_profile_id,
      therapist_name: slot.therapist_profile&.full_name,
      starts_at: slot.starts_at,
      ends_at: slot.ends_at,
      status: slot.status,
      booked: slot.booked?
    }
  end
end
