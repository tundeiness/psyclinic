require "rails_helper"

RSpec.describe "Normal session booking (v2 block flow)", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    AppSetting.current.update!(
      assessment_session_price_cents: 5_000_000,
      block_full_price_cents: 30_000_000
    )
  end

  def make_slot(starts: 2.days.from_now)
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: starts,
      ends_at: starts + 1.hour,
      status: :approved
    )
  end

  def make_paid_block(client: cp, therapist_profile: tp, sessions_used: 0)
    block = SessionBlock.create!(
      client_profile: client,
      therapist_profile: therapist_profile,
      purchased_at: Time.current,
      sessions_total: 6,
      sessions_used: sessions_used,
      payment_mode: :full,
      status: :active
    )
    payment = Payment.create!(
      payable: block,
      client_profile: client,
      amount_cents: 30_000_000,
      currency: "USD",
      status: :succeeded,
      paid_at: Time.current
    )
    block.update!(first_payment_id: payment.id)
    block
  end

  describe "normal session with active paid block" do
    before do
      cp.update!(current_therapist: tp)
      @block = make_paid_block
    end

    it "books successfully and decrements the block's sessions_used" do
      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )

      expect(result.success?).to be(true)
      expect(result.appointment.status).to eq("booked")
      expect(result.appointment.session_block_id).to eq(@block.id)
      expect(@block.reload.sessions_used).to eq(1)
      # No payment intent for a normal session — funded by the block.
      expect(result.payment).to be_nil
    end

    it "marks the block completed after the 6th session" do
      @block.update!(sessions_used: 5)
      slot = make_slot
      BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(@block.reload.sessions_used).to eq(6)
      expect(@block.reload.status).to eq("completed")
    end
  end

  describe "error paths" do
    it "rejects when the client has no current therapist" do
      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/assessment session first/i)
    end

    it "rejects when slot belongs to a different therapist" do
      cp.update!(current_therapist: tp)
      make_paid_block
      other_tp = create(:user, :therapist).therapist_profile
      foreign_slot = AvailabilitySlot.create!(
        therapist_profile: other_tp,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: foreign_slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/current therapist/i)
    end

    it "rejects when no active block exists" do
      cp.update!(current_therapist: tp)
      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/active session block/i)
    end

    it "rejects when block exists but first_payment is still pending" do
      cp.update!(current_therapist: tp)
      block = SessionBlock.create!(
        client_profile: cp,
        therapist_profile: tp,
        purchased_at: Time.current,
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
        status: :pending
      )
      block.update!(first_payment_id: payment.id)

      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/hasn't been paid/i)
    end
  end
end
