require "rails_helper"

RSpec.describe "Payment + booking flow" do
  include ActiveJob::TestHelper

  let(:therapist_user) { create(:user, :therapist) }
  let(:client_user)    { create(:user, :client) }
  let(:tp)             { therapist_user.therapist_profile }
  let(:cp)             { client_user.client_profile }

  before do
    tp.update!(hourly_rate_cents: 9_000)
    ActionMailer::Base.deliveries.clear
  end

  def make_slot
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 2.days.from_now,
      ends_at: 2.days.from_now + 1.hour,
      status: :approved
    )
  end

  describe "BookAppointment" do
    it "creates a pending_payment appointment and a pending payment intent" do
      slot = make_slot
      result = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id)

      expect(result.success?).to be(true)
      expect(result.appointment.status).to eq("pending_payment")
      expect(result.payment.status).to eq("pending")
      expect(result.payment.amount_cents).to eq(9_000)
      expect(result.payment.provider_reference).to be_present
      # Slot is reserved while payment is in flight.
      expect(slot.reload.booked?).to be(true)
    end

    it "still prevents double-booking while payment is pending" do
      slot = make_slot
      BookAppointment.call(client_profile: cp, availability_slot_id: slot.id)

      other = create(:user, :client).client_profile
      second = BookAppointment.call(client_profile: other, availability_slot_id: slot.id)
      expect(second.success?).to be(false)
      expect(second.error).to match(/already booked/i)
    end
  end

  describe "ConfirmPayment success" do
    it "books the appointment, notifies and emails the therapist" do
      slot = make_slot
      booking = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id)

      perform_enqueued_jobs do
        result = ConfirmPayment.call(payment: booking.payment)
        expect(result.success?).to be(true)
      end

      expect(booking.payment.reload.status).to eq("succeeded")
      expect(booking.payment.paid_at).to be_present
      expect(booking.appointment.reload.status).to eq("booked")
      expect(therapist_user.notifications.where(kind: "appointment_booked")).to be_exist
      expect(ActionMailer::Base.deliveries.map(&:subject))
        .to include(a_string_matching(/new appointment booked/i))
    end
  end

  describe "ConfirmPayment failure" do
    it "marks payment failed, releases the slot, no therapist notice" do
      slot = make_slot
      booking = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id)

      result = ConfirmPayment.call(
        payment: booking.payment,
        gateway_params: { force_failure: true }
      )

      expect(result.success?).to be(false)
      expect(booking.payment.reload.status).to eq("failed")
      expect(booking.appointment.reload.status).to eq("payment_failed")
      # Slot is released — someone else can now book it.
      expect(slot.reload.booked?).to be(false)
      expect(therapist_user.notifications.where(kind: "appointment_booked")).not_to be_exist

      rebooking = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id)
      expect(rebooking.success?).to be(true)
    end
  end

  describe "gateway is pluggable" do
    it "uses whatever PaymentGateways.current returns" do
      expect(PaymentGateways.current).to be_a(PaymentGateways::Fake)
    end
  end
end
