# Initiates the purchase of a 6-session block for a client, with a
# given therapist (which must be the client's current_therapist). The
# block is created in a pending state (sessions_used = 0, no payments
# attached yet) along with a Payment in :pending status. The webhook
# flow later marks the block "active" once the payment succeeds.
#
# Phase 6 ships full-payment only. Installment-mode (60/40) lands in
# Phase 7 and will mostly extend this service with a payment_mode
# argument.
class PurchaseSessionBlock
  Result = Struct.new(:success?, :session_block, :payment, :error,
    keyword_init: true)

  class PurchaseError < StandardError; end

  def self.call(...) = new(...).call

  def initialize(client_profile:, payment_mode: :full)
    @client_profile = client_profile
    @payment_mode = payment_mode.to_sym
  end

  def call
    block = nil
    payment = nil

    ActiveRecord::Base.transaction do
      tp_id = @client_profile.current_therapist_id
      if tp_id.nil?
        raise PurchaseError,
          "You must complete an assessment session before buying a block. " \
          "Book an assessment first."
      end

      # One active or pending block at a time per client. Surfaces a
      # clean error rather than allowing two blocks to exist
      # simultaneously (which would confuse the booking flow).
      existing = @client_profile.session_blocks
        .where(status: :active)
        .where("sessions_used < sessions_total")
        .exists?
      if existing
        raise PurchaseError,
          "You already have an active block with sessions remaining."
      end

      amount_cents =
        case @payment_mode
        when :full
          AppSetting.current.block_full_price_cents.to_i
        when :installment
          # First installment: 60% (computed via AppSetting helper so
          # any rounding stays consistent with the second installment).
          AppSetting.current.installment_first_amount_cents.to_i
        else
          raise PurchaseError, "Unknown payment_mode: #{@payment_mode}"
        end

      # Create the block in active status. Sessions_used=0. We don't
      # use a separate "pending block" status — if the payment fails,
      # we mark the block forfeited (or delete it; see Phase 7).
      # For Phase 6 the block is logically inactive until the
      # webhook fires; ConfirmPayment will not "do" anything special
      # to a block-payment because the block is already created. Any
      # booking logic must check that the block's payment is
      # succeeded before letting the client book against it.
      block = SessionBlock.create!(
        client_profile: @client_profile,
        therapist_profile_id: tp_id,
        purchased_at: Time.current,
        sessions_total: 6,
        sessions_used: 0,
        payment_mode: @payment_mode,
        status: :active
      )

      payment = Payment.create!(
        payable: block,
        client_profile: @client_profile,
        amount_cents: amount_cents,
        currency: "USD",  # legacy field; amounts are in kobo
        status: :pending
      )

      intent = PaymentGateways.current.create_intent(payment)
      payment.update!(
        provider: intent[:provider],
        provider_reference: intent[:provider_reference],
        provider_payload: intent[:payload] || {}
      )

      # Tie the payment back via the explicit first_payment_id pointer
      # too — that's the field Phase 7 uses for installment math.
      block.update!(first_payment_id: payment.id)
    end

    Result.new(success?: true, session_block: block, payment: payment)
  rescue PurchaseError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end
end
