# Processes a Stripe-shaped webhook event (mock or real). Idempotent:
# replaying the same event for the same Payment is a no-op.
#
# Used by:
#  - Api::V1::Webhooks::StripeController (real Stripe, when wired)
#  - Api::V1::Dev::MockGatewayController (mock checkout simulator)
#
# The actual side effects of confirming a payment (flipping the
# appointment status, setting current_therapist for assessment
# sessions, notifying the therapist) live in ConfirmPayment so the
# logic is shared with the legacy direct-confirm flow.
class ProcessStripeEvent
  Result = Struct.new(:success?, :payment, :appointment, :session_block,
    :error, :ignored, keyword_init: true)

  HANDLED_TYPES = %w[
    payment_intent.succeeded
    payment_intent.payment_failed
  ].freeze

  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @event = event.with_indifferent_access
  end

  def call
    event_id = @event[:id]
    type = @event[:type]
    intent = @event.dig(:data, :object) || {}
    intent_id = intent[:id]

    unless HANDLED_TYPES.include?(type)
      # Stripe sends many event types we don't care about. Ack with
      # 200 to stop retries, but mark this event as ignored.
      return Result.new(success?: true, ignored: true)
    end

    return error_result("event missing id") if event_id.blank?
    return error_result("event missing payment intent id") if intent_id.blank?

    payment = Payment.find_by(provider_reference: intent_id)
    if payment.nil?
      # Unknown intent — possible if a webhook arrives for a payment
      # we never created (e.g., test event from Stripe dashboard).
      # Ack-and-ignore so retries stop.
      return Result.new(success?: true, ignored: true)
    end

    # Idempotency: this event already processed for this payment?
    # Don't double-confirm / double-notify.
    if payment.processed_event_ids.include?(event_id)
      payable = payment.payable
      return Result.new(success?: true, payment: payment,
        appointment: payable.is_a?(Appointment) ? payable : nil,
        session_block: payable.is_a?(SessionBlock) ? payable : nil,
        ignored: true)
    end

    outcome = (type == "payment_intent.succeeded") ? :succeeded : :failed

    # Record the event id BEFORE delegating so a crash mid-delegation
    # doesn't leave us reprocessing the same event on retry. Wrap in
    # a transaction so the record-event-id and the confirm-side-effects
    # are atomic.
    result = nil
    ActiveRecord::Base.transaction do
      payment.update!(
        processed_event_ids: payment.processed_event_ids + [event_id]
      )

      result = ConfirmPayment.call(
        payment: payment,
        gateway_params: {
          preconfirmed: true,
          outcome: outcome,
          payload: { "event_id" => event_id, "via" => "webhook" }
        }
      )
    end

    Result.new(
      success?: result.success?,
      payment: result.payment,
      appointment: result.appointment,
      session_block: result.session_block,
      error: result.error
    )
  end

  private

  def error_result(msg)
    Result.new(success?: false, error: msg)
  end
end
