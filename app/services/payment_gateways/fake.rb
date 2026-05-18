module PaymentGateways
  # Development/test gateway. Simulates Stripe's PaymentIntent lifecycle
  # without any network calls. create_intent mints a fake intent id +
  # client secret; confirm succeeds unless the caller passes
  # force_failure: true (so failure paths are testable).
  class Fake < Base
    def create_intent(payment)
      reference = "pi_fake_#{SecureRandom.hex(12)}"
      secret = "#{reference}_secret_#{SecureRandom.hex(8)}"
      {
        provider: "fake",
        provider_reference: reference,
        client_secret: secret,
        payload: {
          "simulated" => true,
          "amount_cents" => payment.amount_cents,
          "client_secret" => secret
        }
      }
    end

    def confirm(payment, params = {})
      if params[:force_failure]
        { succeeded: false, reference: payment.provider_reference,
          payload: { "simulated" => true, "result" => "failed" } }
      else
        { succeeded: true, reference: payment.provider_reference,
          payload: { "simulated" => true, "result" => "succeeded" } }
      end
    end
  end
end
