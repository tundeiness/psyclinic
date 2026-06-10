require "rails_helper"

RSpec.describe "Phase 13: 6-week block expiry", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  # Helpers for building blocks and held appointments past or within
  # the 6-week window. AvailabilitySlot rejects past starts_at via
  # validations, so we create with future times and update_columns.
  #
  # SessionBlock requires :purchased_at; Payment is polymorphic to
  # SessionBlock (payable_type/payable_id) and requires client_profile.
  # We create the block first (no first_payment), then the payment
  # with proper polymorphic refs, then point the block at the
  # payment via update_columns (avoiding validate-on-save loops).
  def make_paid_block(purchased_at:, first_paid_at:)
    block = SessionBlock.create!(
      client_profile: cp,
      therapist_profile: tp,
      purchased_at: purchased_at,
      sessions_total: 6,
      sessions_used: 0,
      payment_mode: :full,
      status: :active
    )
    payment = Payment.create!(
      payable: block,
      client_profile: cp,
      amount_cents: 30_000_000,
      currency: "USD",
      status: :succeeded,
      paid_at: first_paid_at,
      provider_reference: SecureRandom.uuid
    )
    block.update_columns(first_payment_id: payment.id)
    block.reload
  end

  def make_held_session(block:, held_at:, status: :completed)
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.year.from_now,
      ends_at: 1.year.from_now + 1.hour,
      status: :approved
    )
    slot.update_columns(starts_at: held_at, ends_at: held_at + 1.hour)
    appt = Appointment.new(
      client_profile: cp,
      therapist_profile: tp,
      availability_slot: slot,
      session_block: block,
      status: status
    )
    appt.save!(validate: false)
    appt
  end

  describe "SessionBlock#expires_at" do
    it "returns first_payment.paid_at + 6 weeks when no session held yet" do
      block = make_paid_block(
        purchased_at: 1.day.ago,
        first_paid_at: 1.day.ago
      )
      expect(block.last_held_at).to be_nil
      expect(block.expires_at).to be_within(1.second).of(1.day.ago + 6.weeks)
      expect(block.expired?).to be(false)
    end

    it "returns last_held_at + 6 weeks when a session has been completed" do
      block = make_paid_block(
        purchased_at: 10.weeks.ago,
        first_paid_at: 10.weeks.ago
      )
      held = 8.weeks.ago
      make_held_session(block: block, held_at: held, status: :completed)
      expect(block.last_held_at).to be_within(1.second).of(held)
      expect(block.expires_at).to be_within(1.second).of(held + 6.weeks)
    end

    it "uses the MOST RECENT held session as anchor" do
      block = make_paid_block(
        purchased_at: 10.weeks.ago,
        first_paid_at: 10.weeks.ago
      )
      make_held_session(block: block, held_at: 5.weeks.ago, status: :completed)
      most_recent = 1.week.ago
      make_held_session(block: block, held_at: most_recent, status: :completed)
      expect(block.last_held_at).to be_within(1.second).of(most_recent)
    end

    it "counts :no_show as held (per Phase 12)" do
      block = make_paid_block(
        purchased_at: 10.weeks.ago,
        first_paid_at: 10.weeks.ago
      )
      held = 2.weeks.ago
      make_held_session(block: block, held_at: held, status: :no_show)
      expect(block.last_held_at).to be_within(1.second).of(held)
    end

    it "does not count :cancelled appointments as held" do
      block = make_paid_block(
        purchased_at: 10.weeks.ago,
        first_paid_at: 10.weeks.ago
      )
      make_held_session(block: block, held_at: 1.week.ago, status: :cancelled)
      expect(block.last_held_at).to be_nil
    end
  end

  describe "SessionBlock#expired?" do
    it "true when no session and >6 weeks since first payment" do
      block = make_paid_block(
        purchased_at: 7.weeks.ago,
        first_paid_at: 7.weeks.ago
      )
      expect(block.expired?).to be(true)
    end

    it "false at exactly 5 weeks since first payment" do
      block = make_paid_block(
        purchased_at: 5.weeks.ago,
        first_paid_at: 5.weeks.ago
      )
      expect(block.expired?).to be(false)
    end

    it "false when a recent session resets the clock" do
      block = make_paid_block(
        purchased_at: 10.weeks.ago,
        first_paid_at: 10.weeks.ago
      )
      make_held_session(block: block, held_at: 1.week.ago, status: :completed)
      expect(block.expired?).to be(false)
    end
  end

  describe "ExpireStaleBlocks" do
    it "flips active blocks past their expiry to :expired" do
      block = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      expect(block.expired?).to be(true)
      expect(block.status).to eq("active")

      result = ExpireStaleBlocks.call(client_profile: cp)
      expect(result.expired_count).to eq(1)
      expect(block.reload.status).to eq("expired")
    end

    it "leaves active blocks within the window alone" do
      block = make_paid_block(
        purchased_at: 2.weeks.ago,
        first_paid_at: 2.weeks.ago
      )
      result = ExpireStaleBlocks.call(client_profile: cp)
      expect(result.expired_count).to eq(0)
      expect(block.reload.status).to eq("active")
    end

    it "is idempotent" do
      block = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      ExpireStaleBlocks.call(client_profile: cp)
      result2 = ExpireStaleBlocks.call(client_profile: cp)
      expect(result2.expired_count).to eq(0)
      expect(block.reload.status).to eq("expired")
    end

    it "scopes by client when provided" do
      block_mine = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      other_client = create(:user, :client).client_profile
      other_client.update!(current_therapist: tp)
      sign_contract_for!(other_client)
      # Build the other client's block via the same factory pattern
      # — but parameterized on which client_profile it belongs to.
      block_other = SessionBlock.create!(
        client_profile: other_client,
        therapist_profile: tp,
        purchased_at: 8.weeks.ago,
        sessions_total: 6,
        sessions_used: 0,
        payment_mode: :full,
        status: :active
      )
      other_payment = Payment.create!(
        payable: block_other,
        client_profile: other_client,
        amount_cents: 30_000_000, currency: "USD",
        status: :succeeded, paid_at: 8.weeks.ago,
        provider_reference: SecureRandom.uuid
      )
      block_other.update_columns(first_payment_id: other_payment.id)

      ExpireStaleBlocks.call(client_profile: cp)
      expect(block_mine.reload.status).to eq("expired")
      expect(block_other.reload.status).to eq("active")  # untouched
    end
  end

  describe "BookAppointment rejects expired blocks" do
    it "returns a clear error message when trying to book on an expired block" do
      block = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      # Block must be expired but still :active (sweeper hasn't run)
      # to exercise the runtime expiry check in BookAppointment.
      expect(block.expired?).to be(true)
      expect(block.status).to eq("active")

      slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )

      r = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(r.success?).to be(false)
      expect(r.error).to match(/expired/i)
    end

    it "returns the 'expired — buy a new block' message after sweep" do
      block = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      ExpireStaleBlocks.call(client_profile: cp)
      expect(block.reload.status).to eq("expired")

      slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )

      r = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(r.success?).to be(false)
      expect(r.error).to match(/expired.*purchase a new block/i)
    end
  end

  describe "PurchaseSessionBlock after expiry" do
    it "allows buying a new block once the previous one expired" do
      old_block = make_paid_block(
        purchased_at: 8.weeks.ago,
        first_paid_at: 8.weeks.ago
      )
      expect(old_block.expired?).to be(true)

      r = PurchaseSessionBlock.call(
        client_profile: cp,
        payment_mode: :full
      )
      expect(r.success?).to be(true)
    end
  end
end
