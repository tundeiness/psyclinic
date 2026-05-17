class PaymentSerializer
  def self.call(payment)
    return nil if payment.nil?

    {
      id: payment.id,
      appointment_id: payment.appointment_id,
      amount_cents: payment.amount_cents,
      amount: payment.amount,
      currency: payment.currency,
      status: payment.status,
      provider: payment.provider,
      provider_reference: payment.provider_reference,
      # The client secret is what a real Stripe.js front end would use to
      # complete the payment. Surfaced from the stored intent payload.
      client_secret: payment.provider_payload["client_secret"],
      paid_at: payment.paid_at
    }
  end
end
