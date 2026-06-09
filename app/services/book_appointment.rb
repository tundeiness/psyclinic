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
          # v2 normal session: client must have a current therapist,
          # the slot must belong to that therapist, and they must
          # have an active block with sessions remaining and the
          # up-front payment succeeded.
          cp_current_tp = @client_profile.current_therapist_id
          if cp_current_tp.nil?
            raise BookingError,
              "Book an assessment session first to choose a therapist."
          end
          if slot.therapist_profile_id != cp_current_tp
            raise BookingError,
              "You can only book normal sessions with your current therapist."
          end

          # Find an active block with this therapist that has paid
          # up-front and has sessions remaining.
          block = @client_profile.session_blocks
            .where(therapist_profile_id: cp_current_tp, status: :active)
            .where("sessions_used < sessions_total")
            .order(purchased_at: :asc)
            .first

          if block.nil?
            raise BookingError,
              "You need an active session block to book a normal session. " \
              "Buy a block first."
          end

          # Block exists but the up-front payment hasn't succeeded
          # yet? Don't let them book on credit.
          if block.first_payment.nil? || !block.first_payment.succeeded?
            raise BookingError,
              "Your block purchase hasn't been paid yet. Complete payment first."
          end

          # Phase 7 will check installment-due here. For Phase 6 we
          # don't gate on it since installment mode isn't shipped yet.

          @session_block = block

          # Normal sessions don't have an additional charge — they're
          # paid via the block. Payment row still gets created with
          # amount 0 so the booking flow remains uniform.
          0
        else
          raise BookingError, "Unknown session_kind: #{@session_kind}"
        end

      appointment = Appointment.new(
        client_profile: @client_profile,
        therapist_profile_id: slot.therapist_profile_id,
        availability_slot: slot,
        reason: @reason,
        # Normal sessions go straight to :booked since they're funded
        # by the block — no separate payment intent needed.
        status: @session_kind == :normal ? :booked : :pending_payment,
        session_kind: @session_kind,
        session_block_id: @session_block&.id
      )
      unless appointment.save
        raise BookingError, appointment.errors.full_messages.to_sentence
      end

      # Normal session: decrement the block, no payment intent needed.
      if @session_kind == :normal
        @session_block.update!(sessions_used: @session_block.sessions_used + 1)
        # Mark block completed if this was the last session.
        if @session_block.sessions_used >= @session_block.sessions_total
          @session_block.update!(status: :completed)
        end
        # No payment intent — return appointment with payment: nil.
        return Result.new(success?: true, appointment: appointment, payment: nil)
      end

      # Assessment session: existing flow — create Payment + intent.
      payment = Payment.create!(
        payable: appointment,
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
