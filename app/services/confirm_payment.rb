# Finalizes a pending payment. Idempotent: re-calling on an already
# succeeded payment is a no-op return. Used by both:
#  - ProcessStripeEvent (webhook-driven, real Stripe + dev mock)
#  - Api::V1::Client::PaymentsController#confirm (legacy direct flow,
#    kept for backward compat)
#
# v2: branches on payable_type since a Payment can now attach to
# either an Appointment (assessment session) or a SessionBlock
# (block purchase).
#
# Side effects of a successful confirmation by payable type:
#
#  Appointment (assessment session):
#    - Payment :pending -> :succeeded
#    - Appointment :pending_payment -> :booked
#    - If no current_therapist on the client yet, bind them to this
#      therapist (v2 model).
#    - Notify the therapist via in-app + email.
#
#  SessionBlock (block purchase):
#    - Payment :pending -> :succeeded
#    - Block status stays :active (it was created active); the
#      booking flow gates on the FIRST PAYMENT being succeeded
#      before allowing normal-session bookings.
#    - Notify the client that their block is ready.
class ConfirmPayment
  Result = Struct.new(:success?, :payment, :appointment, :session_block,
    :error, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(payment:, gateway_params: {})
    @payment = payment
    @gateway_params = gateway_params
  end

  def call
    # Reload from DB so guards below see authoritative current state,
    # not whatever the caller's in-memory record happens to hold. The
    # webhook flow loads Payment.find_by(provider_reference:) fresh,
    # but other callers (services, tests, retries) may pass a stale
    # reference — defending here is cheaper than auditing every site.
    @payment.reload

    return already(@payment) if @payment.succeeded?

    # v2 Phase 7.1: an already-expired payment must not be revivable
    # by a late webhook. ExpireStalePayments marks the payment :failed
    # and stamps expired_at; if we see either signal, ack the event
    # at the dispatch level (success?: true so callers don't 500)
    # but take NO state-changing action — the payment stays expired,
    # the slot stays released.
    if @payment.failed? || @payment.expired_at.present?
      return Result.new(success?: true, payment: @payment,
        appointment: @payment.payable.is_a?(Appointment) ? @payment.payable : nil,
        session_block: @payment.payable.is_a?(SessionBlock) ? @payment.payable : nil,
        error: "Payment already expired or failed; ignoring late event")
    end

    # The legacy flow goes through the gateway's confirm method to
    # decide success vs failure. The webhook flow has already decided
    # — Stripe's event tells us — so callers can pass
    # gateway_params: { preconfirmed: true, outcome: :succeeded } to
    # skip the gateway round-trip.
    outcome =
      if @gateway_params[:preconfirmed]
        { succeeded: @gateway_params[:outcome] == :succeeded,
          reference: @payment.provider_reference,
          payload: @gateway_params[:payload] || {} }
      else
        PaymentGateways.current.confirm(@payment, @gateway_params)
      end

    payable = @payment.payable

    if outcome[:succeeded]
      apply_success(payable, outcome)
      notify_success(payable)
      Result.new(success?: true, payment: @payment,
        appointment: payable.is_a?(Appointment) ? payable : nil,
        session_block: payable.is_a?(SessionBlock) ? payable : nil)
    else
      apply_failure(payable, outcome)
      Result.new(success?: false, payment: @payment,
        appointment: payable.is_a?(Appointment) ? payable : nil,
        session_block: payable.is_a?(SessionBlock) ? payable : nil,
        error: "Payment failed")
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

  def apply_success(payable, outcome)
    ActiveRecord::Base.transaction do
      @payment.mark_succeeded!(
        reference: outcome[:reference],
        payload: outcome[:payload] || {}
      )

      case payable
      when Appointment
        payable.update!(status: :booked)

        # v2: assessment sessions establish the client-therapist
        # binding. Only set if not already set — switching therapists
        # later goes through a different flow with its own checks.
        if payable.assessment?
          cp = payable.client_profile
          if cp.current_therapist_id.nil?
            cp.update!(current_therapist_id: payable.therapist_profile_id)
          end
        end
      when SessionBlock
        # Block already created with :active status; no state flip.
        # Sessions remain unbookable until block.first_payment is
        # :succeeded (the booking flow gates on this). The
        # mark_succeeded! call above is what makes the block usable.
      end
    end
  end

  def apply_failure(payable, outcome)
    ActiveRecord::Base.transaction do
      @payment.mark_failed!(payload: outcome[:payload] || {})

      case payable
      when Appointment
        payable.update!(status: :payment_failed)
      when SessionBlock
        # Differentiate first vs second installment.
        # First-payment failure: block was never funded — forfeit.
        # Second-installment failure: block already paid 60% and is
        # in use; leave it active so the client can retry the 40%
        # via the pay_installment endpoint. Clear second_payment_id
        # so they can re-initiate (otherwise installment_due? would
        # stay "due" forever pointing at a dead payment).
        if @payment.id == payable.first_payment_id
          payable.update!(status: :forfeited,
            notes: "Block purchase payment failed at #{Time.current.iso8601}")
        elsif @payment.id == payable.second_payment_id
          payable.update!(second_payment_id: nil)
        else
          # Unknown payment association — surface in notes for audit.
          payable.update!(
            notes: "Unrecognized failed payment #{@payment.id} at " \
                   "#{Time.current.iso8601}"
          )
        end
      end
    end
  end

  def already(payment)
    payable = payment.payable
    Result.new(success?: true, payment: payment,
      appointment: payable.is_a?(Appointment) ? payable : nil,
      session_block: payable.is_a?(SessionBlock) ? payable : nil)
  end

  def notify_success(payable)
    case payable
    when Appointment
      notify_therapist_of_appointment(payable)
    when SessionBlock
      notify_client_of_block(payable)
    end
  end

  def notify_therapist_of_appointment(appointment)
    therapist_user = appointment.therapist_profile.user
    Notify.call(
      user: therapist_user,
      kind: "appointment_booked",
      title: "New appointment booked",
      body: "A client booked and paid for a session with you.",
      subject: appointment
    )
    AppointmentMailer.booked(appointment).deliver_later
  end

  def notify_client_of_block(block)
    client_user = block.client_profile.user
    Notify.call(
      user: client_user,
      kind: "session_block_ready",
      title: "Your session block is ready",
      body: "You can now book up to #{block.sessions_total} normal sessions " \
            "with #{block.therapist_profile.full_name}.",
      subject: block
    )
    # Email notification could go here when an appropriate mailer
    # template exists — kept to in-app for now.
  end
end
