require "rails_helper"

RSpec.describe "Intake form endpoints", type: :request do
  let(:therapist_user) { create(:user, :therapist) }
  let(:other_therapist) { create(:user, :therapist) }
  let(:admin) { create(:user, :admin) }
  let(:client_user) { create(:user, :client) }
  let(:client_profile) { client_user.client_profile }

  # Same helper pattern as the EMR spec — bypass validation to create a
  # historic appointment that establishes the therapist-client link.
  def establish_relationship(t, c)
    tp = t.therapist_profile
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      status: :approved
    )
    Appointment.new(
      client_profile: c.client_profile,
      therapist_profile: tp,
      availability_slot: slot,
      status: :booked
    ).save!(validate: false)
  end

  # v2 model: the therapist must also be the client's CURRENT
  # therapist for the EMR ability rules to grant access.
  def set_current_therapist(t, c)
    c.client_profile.update!(current_therapist: t.therapist_profile)
  end

  describe "GET /api/v1/clients/:client_id/intake_form" do
    before do
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
    end

    it "404s when no intake form exists yet" do
      get "/api/v1/clients/#{client_profile.id}/intake_form",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:not_found)
    end

    it "returns the intake form when one exists" do
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user,
        presenting_complaint: "anxiety"
      )
      get "/api/v1/clients/#{client_profile.id}/intake_form",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("intake_form", "presenting_complaint"))
        .to eq("anxiety")
    end

    it "forbids a therapist with no relationship to the client" do
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user
      )
      get "/api/v1/clients/#{client_profile.id}/intake_form",
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
    end

    it "lets admin read any client's intake" do
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user
      )
      get "/api/v1/clients/#{client_profile.id}/intake_form",
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
    end

    it "forbids the client themself" do
      IntakeForm.create!(client_profile: client_profile, author: therapist_user)
      get "/api/v1/clients/#{client_profile.id}/intake_form",
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/clients/:client_id/intake_form" do
    before do
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
    end

    it "creates a new intake with structured + JSONB fields" do
      payload = {
        intake_form: {
          presenting_complaint: "anxiety with panic episodes",
          medications: [
            { drug: "Sertraline", dosage: "50mg", started: "2024-01",
              ends: "", medical_condition: "anxiety" }
          ],
          history: [
            { period: "2010-2014", career_academic_event: "University",
              social_details: "moved cities" }
          ]
        }
      }
      post "/api/v1/clients/#{client_profile.id}/intake_form",
        params: payload, as: :json,
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("intake_form", "medications").length).to eq(1)
      expect(body.dig("intake_form", "medications", 0, "drug")).to eq("Sertraline")
      expect(body.dig("intake_form", "signed")).to be(false)
    end

    it "rejects a second create — one intake per client" do
      IntakeForm.create!(client_profile: client_profile, author: therapist_user)
      post "/api/v1/clients/#{client_profile.id}/intake_form",
        params: { intake_form: { presenting_complaint: "x" } }, as: :json,
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "details").join)
        .to match(/already has an intake form/)
    end
  end

  describe "PATCH /api/v1/clients/:client_id/intake_form" do
    let!(:intake) {
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user,
        presenting_complaint: "original"
      )
    }

    it "updates an existing unsigned intake" do
      patch "/api/v1/clients/#{client_profile.id}/intake_form",
        params: { intake_form: { presenting_complaint: "updated" } },
        as: :json,
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      expect(intake.reload.presenting_complaint).to eq("updated")
    end

    it "rejects edits to a signed intake" do
      intake.sign!(therapist_user)
      patch "/api/v1/clients/#{client_profile.id}/intake_form",
        params: { intake_form: { presenting_complaint: "tampered" } },
        as: :json,
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(intake.reload.presenting_complaint).to eq("original")
    end
  end

  describe "POST /api/v1/clients/:client_id/intake_form/sign" do
    let!(:intake) {
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
      IntakeForm.create!(client_profile: client_profile, author: therapist_user)
    }

    it "signs the intake and locks it" do
      post "/api/v1/clients/#{client_profile.id}/intake_form/sign",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("intake_form", "signed")).to be(true)
      expect(body.dig("intake_form", "signed_by_name")).to be_present
    end

    it "rejects signing twice" do
      intake.sign!(therapist_user)
      post "/api/v1/clients/#{client_profile.id}/intake_form/sign",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("already_signed")
    end
  end
end
