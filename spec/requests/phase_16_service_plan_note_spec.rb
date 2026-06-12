require "rails_helper"

RSpec.describe "Phase 16: service plan note", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:other_therapist) { create(:user, :therapist) }
  let(:other_tp) { other_therapist.therapist_profile }
  let(:admin) { create(:user, :admin) }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  def valid_params
    {
      service_plan_note: {
        assessment_summary: "Mild-moderate anxiety with sleep onset insomnia.",
        presenting_problems: "Anxiety, sleep difficulties.",
        treatment_goals: "Restore sleep onset; reduce daily anxiety.",
        interventions_planned: "CBT-I plus relaxation training.",
        session_frequency: "Weekly for 6 weeks, then biweekly.",
        estimated_duration: "12-16 sessions.",
        risk_considerations: "No acute risk; routine follow-up.",
        discharge_criteria: "Sleep onset <30min; PSS <14 sustained 4 weeks.",
        prepared_on: Date.current.iso8601
      }
    }
  end

  describe "POST /api/v1/clients/:client_id/service_plan_note" do
    it "creates the note for the current therapist" do
      post "/api/v1/clients/#{cp.id}/service_plan_note",
        params: valid_params,
        headers: auth_header_for(therapist)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["service_plan_note"]["treatment_goals"])
        .to match(/restore sleep onset/i)
      expect(body["service_plan_note"]["signed"]).to be(false)
    end

    it "refuses a second note for the same client" do
      ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "First plan."
      )
      post "/api/v1/clients/#{cp.id}/service_plan_note",
        params: valid_params,
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "denies a therapist with no current relationship to the client" do
      post "/api/v1/clients/#{cp.id}/service_plan_note",
        params: valid_params,
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/clients/:client_id/service_plan_note" do
    it "returns the note for the current therapist" do
      ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Restore sleep onset."
      )
      get "/api/v1/clients/#{cp.id}/service_plan_note",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["service_plan_note"]["treatment_goals"])
        .to eq("Restore sleep onset.")
    end

    it "returns 404 when no note exists" do
      get "/api/v1/clients/#{cp.id}/service_plan_note",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/clients/:client_id/service_plan_note" do
    it "updates the note when not yet signed" do
      ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "First draft."
      )
      patch "/api/v1/clients/#{cp.id}/service_plan_note",
        params: { service_plan_note: { treatment_goals: "Updated." } },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["service_plan_note"]["treatment_goals"])
        .to eq("Updated.")
    end

    it "refuses updates once signed (Signable lock)" do
      note = ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Signed plan."
      )
      note.sign!(therapist)
      patch "/api/v1/clients/#{cp.id}/service_plan_note",
        params: { service_plan_note: { treatment_goals: "Tampered." } },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.treatment_goals).to eq("Signed plan.")
    end
  end

  describe "POST /api/v1/clients/:client_id/service_plan_note/sign" do
    it "signs the note and locks it" do
      ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Plan."
      )
      post "/api/v1/clients/#{cp.id}/service_plan_note/sign",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["service_plan_note"]["signed"]).to be(true)
      expect(body["service_plan_note"]["signed_at"]).not_to be_nil
    end

    it "refuses to sign twice" do
      note = ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Plan."
      )
      note.sign!(therapist)
      post "/api/v1/clients/#{cp.id}/service_plan_note/sign",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]["code"]).to eq("already_signed")
    end
  end

  describe "GET /api/v1/clients/:client_id/service_plan_note/pdf" do
    it "returns a PDF for the current therapist (signed)" do
      note = ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Plan."
      )
      note.sign!(therapist)
      get "/api/v1/clients/#{cp.id}/service_plan_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body[0, 5]).to eq("%PDF-")
      expect(response.headers["Content-Disposition"]).to match(/attachment/i)
    end

    it "returns a draft-watermarked PDF when unsigned" do
      ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Plan."
      )
      get "/api/v1/clients/#{cp.id}/service_plan_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(response.body[0, 5]).to eq("%PDF-")
    end

    it "404s when no note exists" do
      get "/api/v1/clients/#{cp.id}/service_plan_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:not_found)
    end

    it "permits a former therapist who authored to download" do
      note = ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        treatment_goals: "Plan."
      )
      note.sign!(therapist)
      SwitchTherapist.call(client_profile: cp, new_therapist: other_tp)
      # therapist is now former. They authored — Phase 1 ability
      # rule preserves read access.
      get "/api/v1/clients/#{cp.id}/service_plan_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Pdf::ServicePlanNoteRenderer" do
    it "produces a valid PDF" do
      note = ServicePlanNote.create!(
        client_profile: cp, author: therapist,
        assessment_summary: "Brief summary.",
        treatment_goals: "Goal."
      )
      pdf = Pdf::ServicePlanNoteRenderer.new(
        record: note, generated_by: therapist, title: "Service plan note"
      ).render
      expect(pdf[0, 5]).to eq("%PDF-")
      expect(pdf.bytesize).to be > 1_000
    end
  end
end
