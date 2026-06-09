class Payment < ApplicationRecord
  # v2: polymorphic. A Payment now attaches to either an Appointment
  # (legacy + assessment-session payments) or a SessionBlock (block
  # purchases). Both `appointment` and `payable` work — `appointment`
  # is kept as a legacy accessor that resolves through `payable` when
  # the payable is an Appointment, returning nil for block payments.
  belongs_to :payable, polymorphic: true
  belongs_to :client_profile

  # Legacy accessor — many existing callers read payment.appointment
  # directly. Resolve through payable when present so block-payment
  # callers get nil cleanly (rather than blowing up on missing FK).
  belongs_to :appointment, optional: true

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

  # Returns the SessionBlock if this payment is for one, else nil.
  # Convenience for callers that want the block-typed object.
  def session_block
    payable.is_a?(SessionBlock) ? payable : nil
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
