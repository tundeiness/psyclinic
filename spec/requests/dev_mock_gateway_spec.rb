require "rails_helper"

RSpec.describe "Dev mock gateway", type: :request do
  let(:tp_user) { create(:user, :therapist) }
  let(:tp) { tp_user.therapist_profile }
  let(:cp_user) { create(:user, :client) }
  let(:cp) { cp_user.client_profile }

  before do
    AppSetting.current.update!(assessment_session_price_cents: 5_000_000)
  end

  def book_assessment
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 2.days.from_now,
      ends_at: 2.days.from_now + 1.hour,
      status: :approved
    )
    BookAppointment.call(
      client_profile: cp,
      availability_slot_id: slot.id,
      session_kind: :assessment
    )
  end

  describe "POST /api/v1/dev/mock_gateway/:intent/simulate" do
    it "simulating 'succeed' marks the payment succeeded and books the appointment" do
      booking = book_assessment
      intent_id = booking.payment.provider_reference

      post "/api/v1/dev/mock_gateway/#{intent_id}/simulate",
        params: { outcome: "succeed" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["simulated"]).to eq("succeed")
      expect(body["payment_status"]).to eq("succeeded")
      expect(body["appointment_status"]).to eq("booked")

      expect(booking.payment.reload.status).to eq("succeeded")
      expect(booking.appointment.reload.status).to eq("booked")
      expect(cp.reload.current_therapist_id).to eq(tp.id)
    end

    it "simulating 'fail' marks the payment failed and releases the slot" do
      booking = book_assessment
      intent_id = booking.payment.provider_reference

      post "/api/v1/dev/mock_gateway/#{intent_id}/simulate",
        params: { outcome: "fail" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["simulated"]).to eq("fail")
      expect(body["payment_status"]).to eq("failed")
      expect(body["appointment_status"]).to eq("payment_failed")

      # current_therapist NOT set on failed payment
      expect(cp.reload.current_therapist_id).to be_nil
    end

    it "returns 404 for an unknown payment intent" do
      post "/api/v1/dev/mock_gateway/pi_test_nope/simulate",
        params: { outcome: "succeed" }
      expect(response).to have_http_status(:not_found)
    end

    it "rejects unknown actions with 400" do
      booking = book_assessment
      intent_id = booking.payment.provider_reference

      post "/api/v1/dev/mock_gateway/#{intent_id}/simulate",
        params: { outcome: "explode" }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
