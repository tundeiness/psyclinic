module PaymentGateways
  # Stripe-shaped mock gateway. Used in development and test until real
  # Stripe credentials are configured. Mints Stripe-formatted intent
  # ids (`pi_test_...`) and event payloads that match Stripe's webhook
  # event shape. Swapping to real Stripe is a one-file change:
  # implement PaymentGateways::Stripe (also a Base subclass) and flip
  # the constant in `PaymentGateways.current`.
  #
  # Idempotency, signature verification, and webhook dispatch live
  # OUTSIDE the gateway (in the webhook controller + ProcessStripeEvent
  # service) so they're identical for mock and real Stripe.
  class MockStripe < Base
    PROVIDER = "mock_stripe".freeze

    # create_intent: invoked by BookAppointment when creating a Payment.
    # Returns the payment intent id, client secret, and full intent
    # payload — same shape Stripe returns from PaymentIntent.create.
    def create_intent(payment)
      reference = "pi_test_#{SecureRandom.hex(12)}"
      secret = "#{reference}_secret_#{SecureRandom.hex(8)}"
      {
        provider: PROVIDER,
        provider_reference: reference,
        client_secret: secret,
        payload: {
          "id" => reference,
          "object" => "payment_intent",
          "status" => "requires_payment_method",
          "amount" => payment.amount_cents,
          "currency" => (payment.currency || "ngn").downcase,
          "client_secret" => secret,
          "livemode" => false,
          "mock" => true
        }
      }
    end

    # build_event: given a payment intent id and an outcome
    # (:succeeded / :failed), synthesize a Stripe-shaped webhook event
    # payload. The dev simulator endpoint passes the result through
    # to the webhook handler so the same code processes mock and real
    # Stripe events identically.
    def build_event(payment_intent_id:, outcome:, amount_cents: nil)
      raise ArgumentError, "outcome must be :succeeded or :failed" \
        unless %i[succeeded failed].include?(outcome)

      type = outcome == :succeeded ? "payment_intent.succeeded"
                                    : "payment_intent.payment_failed"
      status_str = outcome == :succeeded ? "succeeded" : "requires_payment_method"

      {
        "id" => "evt_test_#{SecureRandom.hex(12)}",
        "object" => "event",
        "type" => type,
        "livemode" => false,
        "created" => Time.current.to_i,
        "data" => {
          "object" => {
            "id" => payment_intent_id,
            "object" => "payment_intent",
            "status" => status_str,
            "amount" => amount_cents,
            "livemode" => false,
            "mock" => true,
            "last_payment_error" => outcome == :failed ? {
              "code" => "card_declined",
              "message" => "Your card was declined (simulated)."
            } : nil
          }
        }
      }
    end
  end
end
