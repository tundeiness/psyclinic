module PaymentGateways
  # Stripe-shaped interface. The real StripeGateway will implement these
  # using Stripe::PaymentIntent; the controller/services only ever talk
  # to this interface so swapping the implementation is a one-line change
  # in PaymentGateways.current.
  #
  #   create_intent(payment) -> {
  #     provider:, provider_reference:, client_secret:, payload:
  #   }
  #   confirm(payment, params = {}) -> {
  #     succeeded: true/false, reference:, payload:
  #   }
  class Base
    def create_intent(_payment)
      raise NotImplementedError
    end

    def confirm(_payment, _params = {})
      raise NotImplementedError
    end
  end
end
