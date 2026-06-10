require "rails_helper"

RSpec.describe "Session note endpoints", type: :request do
  let(:therapist_user) { create(:user, :therapist) }
  let(:other_therapist) { create(:user, :therapist) }
  let(:admin) { create(:user, :admin) }
  let(:client_user) { create(:user, :client) }
  let(:client_profile) { client_user.client_profile }

  def make_appointment(t, c)
    tp = t.therapist_profile
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      status: :approved
    )
    appt = Appointment.new(
      client_profile: c.client_profile,
      therapist_profile: tp,
      availability_slot: slot,
      status: :booked
    )
    appt.save!(validate: false)
    appt
  end

  def set_current_therapist(t, c)
    c.client_profile.update!(current_therapist: t.therapist_profile)
  end

  describe "GET /api/v1/appointments/:appointment_id/session_note" do
    before { set_current_therapist(therapist_user, client_user) }
    let!(:appointment) { make_appointment(therapist_user, client_user) }

    it "404s when no note exists yet" do
      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:not_found)
    end

    it "returns the note when one exists" do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user,
        review: "good session"
      )
      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_note"]["review"]).to eq("good session")
      expect(body["session_note"]["author_name"]).to be_present
    end

    it "rejects an unrelated therapist's read attempt" do
      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects the client's attempt to read their own session note" do
      # Per the contract: session notes are private to the clinician.
      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "lets admin read" do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user
      )
      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
    end

    it "still allows the original author to read after they're no longer current" do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user,
        review: "first session"
      )
      # Switch the client to another therapist.
      set_current_therapist(other_therapist, client_user)

      get "/api/v1/appointments/#{appointment.id}/session_note",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/appointments/:appointment_id/session_note" do
    before { set_current_therapist(therapist_user, client_user) }
    let!(:appointment) { make_appointment(therapist_user, client_user) }

    it "creates a note for the current therapist" do
      post "/api/v1/appointments/#{appointment.id}/session_note",
        params: {
          session_note: {
            session_number: 1,
            review: "first session went well",
            addressed_and_plan: "explored anxiety triggers",
            clinician_impression: "client engaged"
          }
        },
        headers: auth_header_for(therapist_user)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["session_note"]["review"]).to eq("first session went well")
      expect(body["session_note"]["author_name"]).to be_present
      expect(SessionNote.count).to eq(1)
      expect(SessionNote.last.client_profile_id).to eq(client_profile.id)
    end

    it "forbids creation by a therapist who isn't the current one" do
      post "/api/v1/appointments/#{appointment.id}/session_note",
        params: { session_note: { review: "x" } },
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids creation by a client" do
      post "/api/v1/appointments/#{appointment.id}/session_note",
        params: { session_note: { review: "x" } },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a second note for the same appointment" do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user
      )
      post "/api/v1/appointments/#{appointment.id}/session_note",
        params: { session_note: { review: "second attempt" } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      details = JSON.parse(response.body).dig("error", "details") || []
      expect(details.join(" ")).to match(/already has a session note/i)
    end
  end

  describe "PATCH /api/v1/appointments/:appointment_id/session_note" do
    before { set_current_therapist(therapist_user, client_user) }
    let!(:appointment) { make_appointment(therapist_user, client_user) }
    let!(:note) do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user,
        review: "draft"
      )
    end

    it "updates an unsigned note" do
      patch "/api/v1/appointments/#{appointment.id}/session_note",
        params: { session_note: { review: "updated text" } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      expect(note.reload.review).to eq("updated text")
    end

    it "refuses to update a signed note" do
      note.sign!(therapist_user)
      patch "/api/v1/appointments/#{appointment.id}/session_note",
        params: { session_note: { review: "should not save" } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("already_signed")
      expect(note.reload.review).to eq("draft")
    end
  end

  describe "POST /api/v1/appointments/:appointment_id/session_note/sign" do
    before { set_current_therapist(therapist_user, client_user) }
    let!(:appointment) { make_appointment(therapist_user, client_user) }
    let!(:note) do
      SessionNote.create!(
        appointment: appointment,
        client_profile: client_profile,
        author: therapist_user
      )
    end

    it "signs an unsigned note" do
      post "/api/v1/appointments/#{appointment.id}/session_note/sign",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      note.reload
      expect(note.signed?).to be(true)
      expect(note.signed_by).to eq(therapist_user)
    end

    it "refuses to sign twice" do
      note.sign!(therapist_user)
      post "/api/v1/appointments/#{appointment.id}/session_note/sign",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("already_signed")
    end
  end
end
