# Books an appointment for a client on an approved slot and creates the
# associated Payment (pending) with a gateway payment intent.
#
# v2 behavior:
#  - Assessment sessions: priced at AppSetting.assessment_session_price_cents
#    (~₦50,000). Always paid. No free first booking.
#  - Normal sessions: require an active SessionBlock with sessions
#    remaining. Phase 5.1 stubs this branch with an error since block
#    purchasing lands in Phase 6.
#
# The appointment is created as `pending_payment` so the slot is reserved
# (RESERVING_STATUSES) and cannot be double-booked while payment is in
# flight. ProcessStripeEvent (or ConfirmPayment) later flips it to
# `booked` or `payment_failed`.
#
# Concurrency: the slot row is locked; the DB partial unique index is the
# final backstop against double-booking.
class BookAppointment
  Result = Struct.new(:success?, :appointment, :payment, :error,
    keyword_init: true)

  class BookingError < StandardError; end

  def self.call(...) = new(...).call

  def initialize(client_profile:, availability_slot_id:,
                  session_kind: :normal, reason: nil)
    @client_profile = client_profile
    @availability_slot_id = availability_slot_id
    @session_kind = session_kind.to_sym
    @reason = reason
  end

  def call
    appointment = nil
    payment = nil

    ActiveRecord::Base.transaction do
      slot = AvailabilitySlot.lock.find_by(id: @availability_slot_id)

      raise BookingError, "Slot not found" if slot.nil?
      raise BookingError, "Slot is not available" unless slot.approved?
      raise BookingError, "Slot is already booked" if slot.booked?

      amount_cents =
        case @session_kind
        when :assessment
          AppSetting.current.assessment_session_price_cents.to_i
        when :normal
          # Phase 6 implements block-decrement here. For Phase 5.1
          # we surface an explicit "not yet" error rather than fall
          # back to legacy flat-rate, so callers don't accidentally
          # exercise a half-built code path.
          raise BookingError,
            "Normal session booking requires an active session block " \
            "(coming in a future release). Book an assessment session first."
        else
          raise BookingError, "Unknown session_kind: #{@session_kind}"
        end

      appointment = Appointment.new(
        client_profile: @client_profile,
        therapist_profile_id: slot.therapist_profile_id,
        availability_slot: slot,
        reason: @reason,
        status: :pending_payment,
        session_kind: @session_kind
      )
      unless appointment.save
        raise BookingError, appointment.errors.full_messages.to_sentence
      end

      payment = Payment.create!(
        appointment: appointment,
        client_profile: @client_profile,
        amount_cents: amount_cents,
        # Currency stays USD-string for backward compat with existing
        # tests and dashboard. When real Stripe lands we'll flip this
        # to "NGN" along with the gateway change — the amounts are
        # already stored in the smallest unit (kobo == cents in the
        # database column name) so no math changes.
        currency: "USD",
        status: :pending
      )

      intent = PaymentGateways.current.create_intent(payment)
      payment.update!(
        provider: intent[:provider],
        provider_reference: intent[:provider_reference],
        provider_payload: intent[:payload] || {}
      )
    end

    Result.new(success?: true, appointment: appointment, payment: payment)
  rescue BookingError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordNotUnique
    Result.new(success?: false, error: "Slot is already booked")
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end
end
