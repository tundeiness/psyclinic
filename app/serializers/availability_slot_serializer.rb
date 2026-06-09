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

class AppointmentSerializer
  def self.call(appt)
    base = {
      id: appt.id,
      status: appt.status,
      session_kind: appt.session_kind,
      reason: appt.reason,
      client: {
        id: appt.client_profile_id,
        name: appt.client_profile&.full_name
      },
      therapist: {
        id: appt.therapist_profile_id,
        name: appt.therapist_profile&.full_name
      },
      slot: {
        id: appt.availability_slot_id,
        starts_at: appt.availability_slot&.starts_at,
        ends_at: appt.availability_slot&.ends_at
      },
      created_at: appt.created_at
    }

    # v2: clients need to resume payment if they closed the checkout
    # mid-flow. Include the payment id + intent reference when the
    # appointment is still pending_payment so the dashboard's
    # "Resume" link can route to the checkout page.
    if appt.pending_payment? && appt.payment.present?
      base[:payment] = {
        id: appt.payment.id,
        provider_reference: appt.payment.provider_reference,
        amount_cents: appt.payment.amount_cents
      }
    end

    base
  end
end
