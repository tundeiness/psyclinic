require "rails_helper"

RSpec.describe "Pending payment expiry (Phase 7.1)", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    AppSetting.current.update!(
      assessment_session_price_cents: 5_000_000,
      pending_payment_expiry_minutes: 30
    )
  end

  def make_slot(starts: 3.days.from_now)
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: starts,
      ends_at: starts + 1.hour,
      status: :approved
    )
  end

  def book_assessment(starts: 3.days.from_now)
    BookAppointment.call(
      client_profile: cp,
      availability_slot_id: make_slot(starts: starts).id,
      session_kind: :assessment
    )
  end

  describe "ExpireStalePayments service" do
    it "leaves recent pending payments alone" do
      booking = book_assessment
      result = ExpireStalePayments.call
      expect(result.expired_count).to eq(0)
      expect(booking.appointment.reload.pending_payment?).to be(true)
    end

    it "expires pending payments older than the configured timeout" do
      booking = book_assessment
      # Backdate to 31 minutes ago (past the 30-minute default).
      booking.appointment.update_columns(created_at: 31.minutes.ago)
      result = ExpireStalePayments.call
      expect(result.expired_count).to eq(1)
      expect(booking.appointment.reload.status).to eq("cancelled")
      expect(booking.payment.reload.status).to eq("failed")
      expect(booking.payment.expired_at).to be_present
    end

    it "respects a custom expiry setting" do
      AppSetting.current.update!(pending_payment_expiry_minutes: 5)
      booking = book_assessment
      booking.appointment.update_columns(created_at: 6.minutes.ago)
      result = ExpireStalePayments.call
      expect(result.expired_count).to eq(1)
    end

    it "scoped by client_profile only expires that client's stale ones" do
      other_client = create(:user, :client).client_profile
      mine    = book_assessment
      mine.appointment.update_columns(created_at: 31.minutes.ago)

      other_slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 4.days.from_now,
        ends_at: 4.days.from_now + 1.hour,
        status: :approved
      )
      other = BookAppointment.call(
        client_profile: other_client,
        availability_slot_id: other_slot.id,
        session_kind: :assessment
      )
      other.appointment.update_columns(created_at: 31.minutes.ago)

      ExpireStalePayments.call(client_profile: cp)

      expect(mine.appointment.reload.cancelled?).to be(true)
      expect(other.appointment.reload.pending_payment?).to be(true)
    end

    it "does not touch already-succeeded payments" do
      booking = book_assessment
      ConfirmPayment.call(
        payment: booking.payment,
        gateway_params: { preconfirmed: true, outcome: :succeeded }
      )
      booking.appointment.update_columns(created_at: 31.minutes.ago)
      ExpireStalePayments.call
      expect(booking.payment.reload.status).to eq("succeeded")
      expect(booking.appointment.reload.status).to eq("booked")
    end
  end

  describe "BookAppointment integration" do
    it "expires the client's stale pending payments before booking a new one" do
      first = book_assessment(starts: 3.days.from_now)
      first.appointment.update_columns(created_at: 31.minutes.ago)

      second = book_assessment(starts: 4.days.from_now)

      expect(first.appointment.reload.status).to eq("cancelled")
      expect(first.payment.reload.status).to eq("failed")
      expect(second.success?).to be(true)
      expect(second.appointment.pending_payment?).to be(true)
    end
  end

  describe "Slot listing integration" do
    it "shows a slot as available again after its pending booking expires" do
      slot = make_slot
      booking = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :assessment
      )
      booking.appointment.update_columns(created_at: 31.minutes.ago)

      get "/api/v1/client/availability_slots",
        params: { date: slot.starts_at.to_date.to_s },
        headers: auth_header_for(client_user)

      body = JSON.parse(response.body)
      ids = body["availability_slots"].map { |s| s["id"] }
      expect(ids).to include(slot.id)
    end
  end

  describe "Late webhook guard" do
    it "ignores a 'succeeded' webhook for a payment that's already been expired" do
      booking = book_assessment
      booking.appointment.update_columns(created_at: 31.minutes.ago)
      ExpireStalePayments.call

      # Try to confirm anyway — simulates a late-arriving Stripe webhook.
      result = ConfirmPayment.call(
        payment: booking.payment,
        gateway_params: { preconfirmed: true, outcome: :succeeded }
      )

      # Dispatch ack'd, but no state change.
      expect(booking.payment.reload.status).to eq("failed")
      expect(booking.appointment.reload.status).to eq("cancelled")
      expect(result.error).to match(/expired/i)
    end
  end

  describe "AppointmentSerializer expires_at" do
    it "includes expires_at on pending payments" do
      booking = book_assessment
      get "/api/v1/client/appointments", headers: auth_header_for(client_user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      appt = body["appointments"].find { |a| a["id"] == booking.appointment.id }
      expect(appt.dig("payment", "expires_at")).to be_present
    end
  end
end
