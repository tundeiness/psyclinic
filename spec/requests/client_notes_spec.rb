require "rails_helper"

RSpec.describe "Therapist client notes", type: :request do
  let(:json) { JSON.parse(response.body) }

  # therapist A has seen client X (booked + paid)
  let(:therapist_a) { create(:user, :therapist) }
  let(:tp_a)        { therapist_a.therapist_profile }
  let(:client_x)    { create(:user, :client) }
  let(:cx)          { client_x.client_profile }

  before do
    tp_a.update!(hourly_rate_cents: 5000)
    slot = AvailabilitySlot.create!(
      therapist_profile: tp_a,
      starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour,
      status: :approved
    )
    booking = BookAppointment.call(client_profile: cx, availability_slot_id: slot.id)
    ConfirmPayment.call(payment: booking.payment)
  end

  describe "POST notes (therapist who has seen the client)" do
    it "creates a private note" do
      post "/api/v1/therapist/clients/#{cx.id}/notes",
        params: { note: { body: "Presented with mild anxiety; CBT plan." } },
        headers: auth_header_for(therapist_a)

      expect(response).to have_http_status(:created)
      expect(json.dig("note", "body")).to match(/CBT plan/)
      expect(ClientNote.count).to eq(1)
    end

    it "rejects an empty note" do
      post "/api/v1/therapist/clients/#{cx.id}/notes",
        params: { note: { body: "" } },
        headers: auth_header_for(therapist_a)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET notes" do
    it "lists only this therapist's notes for this client" do
      ClientNote.create!(therapist_profile: tp_a, client_profile: cx, body: "Note 1")
      get "/api/v1/therapist/clients/#{cx.id}/notes",
        headers: auth_header_for(therapist_a)
      expect(response).to have_http_status(:ok)
      expect(json["notes"].size).to eq(1)
      expect(json["notes"].first["body"]).to eq("Note 1")
    end
  end

  describe "security boundary" do
    it "forbids a therapist who has NOT seen the client" do
      therapist_b = create(:user, :therapist)
      post "/api/v1/therapist/clients/#{cx.id}/notes",
        params: { note: { body: "I should not be able to write this" } },
        headers: auth_header_for(therapist_b)
      expect(response).to have_http_status(:forbidden)
      expect(ClientNote.count).to eq(0)
    end

    it "forbids a client from reading notes about themselves" do
      ClientNote.create!(therapist_profile: tp_a, client_profile: cx, body: "private")
      get "/api/v1/therapist/clients/#{cx.id}/notes",
        headers: auth_header_for(client_x)
      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/therapist/clients/#{cx.id}/notes"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
