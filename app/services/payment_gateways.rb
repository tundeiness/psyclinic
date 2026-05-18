module PaymentGateways
  # Single place that decides which gateway implementation is live.
  # To go live with Stripe later: implement PaymentGateways::Stripe
  # (subclass of Base, using Stripe::PaymentIntent) and switch the
  # constant below — nothing else in the app needs to change.
  def self.current
    @current ||= Fake.new
  end

  # Test hook to inject a specific gateway instance.
  def self.current=(gateway)
    @current = gateway
  end
end
