class Payment < ApplicationRecord
  belongs_to :appointment
  belongs_to :client_profile

  enum :status, {
    pending: 0,
    succeeded: 1,
    failed: 2,
    refunded: 3
  }, default: :pending

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  def amount
    amount_cents / 100.0
  end

  def mark_succeeded!(reference: nil, payload: {})
    update!(
      status: :succeeded,
      paid_at: Time.current,
      provider_reference: reference || provider_reference,
      provider_payload: payload.presence || provider_payload
    )
  end

  def mark_failed!(payload: {})
    update!(status: :failed, provider_payload: payload.presence || provider_payload)
  end
end
