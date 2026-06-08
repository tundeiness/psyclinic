require "rails_helper"

RSpec.describe "Stripe webhook endpoint", type: :request do
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

  def post_event(event_body)
    post "/api/v1/webhooks/stripe",
      params: event_body.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end

  describe "in test/dev mode (no STRIPE_WEBHOOK_SECRET set)" do
    it "accepts unsigned events and processes them" do
      booking = book_assessment
      post_event({
        "id" => "evt_t_1",
        "type" => "payment_intent.succeeded",
        "data" => { "object" => { "id" => booking.payment.provider_reference } }
      })

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["received"]).to be(true)
      expect(booking.payment.reload.status).to eq("succeeded")
    end

    it "returns 200 with ignored=true for irrelevant event types" do
      post_event({
        "id" => "evt_t_x",
        "type" => "customer.subscription.created",
        "data" => { "object" => {} }
      })
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ignored"]).to be(true)
    end

    it "returns 400 for malformed JSON" do
      post "/api/v1/webhooks/stripe",
        params: "not-json",
        headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "production mode (STRIPE_WEBHOOK_SECRET set)" do
    around do |ex|
      ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_dummy"
      ex.run
      ENV.delete("STRIPE_WEBHOOK_SECRET")
    end

    it "rejects events without a valid signature (placeholder verifier returns false)" do
      # Phase 5.1: real HMAC verification not yet implemented. Until
      # then, secret-set means everything is rejected for safety.
      # When real verification lands, this test gets replaced with
      # one that verifies a real HMAC signature.
      post_event({
        "id" => "evt_p_1",
        "type" => "payment_intent.succeeded",
        "data" => { "object" => { "id" => "pi_test_x" } }
      })
      expect(response).to have_http_status(:bad_request)
    end
  end
end
