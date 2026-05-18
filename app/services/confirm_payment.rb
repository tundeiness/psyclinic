# Finalizes a pending payment via the gateway. On success the
# appointment becomes `booked` and the therapist gets an email + an
# in-app notification. On failure the appointment becomes
# `payment_failed`, which releases the slot for others.
#
# In the real Stripe flow this is invoked by a webhook; here the client
# (or a test) calls it after the simulated intent.
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
    outcome = PaymentGateways.current.confirm(@payment, @gateway_params)

    if outcome[:succeeded]
      ActiveRecord::Base.transaction do
        @payment.mark_succeeded!(
          reference: outcome[:reference],
          payload: outcome[:payload] || {}
        )
        appointment.update!(status: :booked)
      end
      notify_therapist(appointment)
      Result.new(success?: true, payment: @payment, appointment: appointment)
    else
      ActiveRecord::Base.transaction do
        @payment.mark_failed!(payload: outcome[:payload] || {})
        appointment.update!(status: :payment_failed)
      end
      Result.new(success?: false, payment: @payment, appointment: appointment,
        error: "Payment failed")
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

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
