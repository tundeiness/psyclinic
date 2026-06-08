# Finalizes a pending payment. Idempotent: re-calling on an already
# succeeded payment is a no-op return. Used by both:
#  - ProcessStripeEvent (webhook-driven, real Stripe + dev mock)
#  - Api::V1::Client::PaymentsController#confirm (legacy direct flow,
#    kept for backward compat)
#
# Side effects of a successful confirmation:
#  - Payment goes to :succeeded
#  - Appointment goes to :booked
#  - If the appointment was an assessment session AND the client has
#    no current_therapist yet, bind them to this therapist (v2 model).
#  - Notify the therapist via in-app + email.
class ConfirmPayment
  Result = Struct.new(:success?, :payment, :appointment, :error, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(payment:, gateway_params: {})
    @payment = payment
    @gateway_params = gateway_params
  end

  def call
    return already(@payment) if @payment.succeeded?

    appointment = @payment.appointment

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

    if outcome[:succeeded]
      apply_success(appointment, outcome)
      notify_therapist(appointment)
      Result.new(success?: true, payment: @payment, appointment: appointment)
    else
      apply_failure(appointment, outcome)
      Result.new(success?: false, payment: @payment, appointment: appointment,
        error: "Payment failed")
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

  def apply_success(appointment, outcome)
    ActiveRecord::Base.transaction do
      @payment.mark_succeeded!(
        reference: outcome[:reference],
        payload: outcome[:payload] || {}
      )
      appointment.update!(status: :booked)

      # v2: assessment sessions establish the client-therapist binding.
      # Only set if not already set — switching therapists later goes
      # through a different flow with its own checks.
      if appointment.assessment?
        cp = appointment.client_profile
        if cp.current_therapist_id.nil?
          cp.update!(current_therapist_id: appointment.therapist_profile_id)
        end
      end
    end
  end

  def apply_failure(appointment, outcome)
    ActiveRecord::Base.transaction do
      @payment.mark_failed!(payload: outcome[:payload] || {})
      appointment.update!(status: :payment_failed)
    end
  end

  def already(payment)
    Result.new(success?: true, payment: payment, appointment: payment.appointment)
  end

  def notify_therapist(appointment)
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
end
