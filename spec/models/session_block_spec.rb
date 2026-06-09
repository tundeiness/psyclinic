require "rails_helper"

RSpec.describe SessionBlock, type: :model do
  let(:therapist) { create(:user, :therapist) }
  let(:client)    { create(:user, :client) }
  let(:tp) { therapist.therapist_profile }
  let(:cp) { client.client_profile }

  def build_block(**attrs)
    SessionBlock.new({
      client_profile: cp,
      therapist_profile: tp,
      purchased_at: Time.current,
      sessions_total: 6,
      sessions_used: 0,
      payment_mode: :full,
      status: :active
    }.merge(attrs))
  end

  describe "defaults + persistence" do
    it "creates with full payment + active status by default" do
      b = build_block
      expect(b.save).to be(true)
      expect(b.payment_mode).to eq("full")
      expect(b.status).to eq("active")
      expect(b.sessions_remaining).to eq(6)
    end
  end

  describe "validations" do
    it "rejects sessions_used > sessions_total" do
      b = build_block(sessions_used: 7)
      expect(b.valid?).to be(false)
      expect(b.errors[:sessions_used].join).to match(/cannot exceed/)
    end

    it "rejects negative sessions_used" do
      b = build_block(sessions_used: -1)
      expect(b.valid?).to be(false)
    end
  end

  describe "#installment_due?" do
    it "returns false for full-paid blocks regardless of sessions used" do
      b = build_block(payment_mode: :full, sessions_used: 5)
      expect(b.installment_due?).to be(false)
    end

    it "returns false on an installment block with 0-2 sessions used" do
      b = build_block(payment_mode: :installment, sessions_used: 2)
      expect(b.installment_due?).to be(false)
    end

    it "returns TRUE on an installment block with 3+ sessions used and no second_payment" do
      b = build_block(payment_mode: :installment, sessions_used: 3)
      expect(b.installment_due?).to be(true)
    end

    it "returns false once second_payment is recorded" do
      appt = build_appointment_for(cp, tp)
      payment = Payment.create!(
        payable: appt,
        appointment: appt,
        client_profile: cp,
        amount_cents: 12_000_000,
        status: :succeeded
      )
      b = build_block(
        payment_mode: :installment,
        sessions_used: 4,
        second_payment: payment
      )
      expect(b.installment_due?).to be(false)
    end
  end

  describe "#sessions_remaining" do
    it "is total minus used" do
      b = build_block(sessions_total: 6, sessions_used: 2)
      expect(b.sessions_remaining).to eq(4)
    end
  end

  # Helper for the Payment-creation case above. Payment currently
  # requires an appointment; the polymorphic refactor lands in Phase 5.
  def build_appointment_for(cp, tp)
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      status: :approved
    )
    Appointment.new(
      client_profile: cp,
      therapist_profile: tp,
      availability_slot: slot,
      status: :booked
    ).tap { |a| a.save!(validate: false) }
  end
end
