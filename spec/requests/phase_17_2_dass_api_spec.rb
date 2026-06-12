require "rails_helper"

RSpec.describe "Phase 17.2: DASS-42 API", type: :request do
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:other_client) { create(:user, :client) }

  before do
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  # Helper: build the full 42-item params hash with a uniform response.
  def full_item_params(response: 1)
    (1..42).each_with_object({}) { |n, h| h[:"item_#{n}"] = response }
  end

  describe "Client surface" do
    describe "POST /api/v1/client/dass_assessments" do
      it "creates a new draft for the client" do
        post "/api/v1/client/dass_assessments",
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["dass_assessment"]["signed"]).to be(false)
        expect(body["dass_assessment"]["completed_items"]).to eq(0)
        # Raw scores must NOT appear in the client serialization (Q7).
        expect(body["dass_assessment"]).not_to have_key("depression_score")
      end

      it "forbids non-clients" do
        post "/api/v1/client/dass_assessments",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/client/dass_assessments" do
      it "lists only the client's own assessments" do
        DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        DassAssessment.create!(
          client_profile: other_client.client_profile,
          author: other_client,
          assessment_date: Date.current
        )
        get "/api/v1/client/dass_assessments",
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["dass_assessments"].size).to eq(1)
      end
    end

    describe "PATCH /api/v1/client/dass_assessments/:id" do
      it "saves partial responses" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        patch "/api/v1/client/dass_assessments/#{d.id}",
          params: { dass_assessment: { item_1: 2, item_2: 3 } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        expect(d.reload.item_1).to eq(2)
        expect(d.item_2).to eq(3)
        # completed_items count reflects partial state.
        expect(JSON.parse(response.body)["dass_assessment"]["completed_items"]).to eq(2)
      end

      it "refuses updates after signing" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        # Fill + sign
        (1..42).each { |n| d["item_#{n}"] = 1 }
        d.save!
        d.sign!(client_user)
        patch "/api/v1/client/dass_assessments/#{d.id}",
          params: { dass_assessment: { item_1: 0 } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]["code"]).to eq("already_signed")
      end

      it "rejects out-of-range Likert values via the model" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        patch "/api/v1/client/dass_assessments/#{d.id}",
          params: { dass_assessment: { item_1: 7 } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "POST /api/v1/client/dass_assessments/:id/submit" do
      it "signs the assessment when all 42 items are present" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        post "/api/v1/client/dass_assessments/#{d.id}/submit",
          params: { dass_assessment: full_item_params(response: 1) },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["dass_assessment"]["signed"]).to be(true)
        # Scores STILL not in the client response after submission.
        expect(body["dass_assessment"]).not_to have_key("depression_score")
        # Severity bands ARE shown to the client (Q7).
        expect(body["dass_assessment"]).to have_key("depression_severity")
      end

      it "refuses incomplete submissions" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        # Only fill 10 items.
        partial = (1..10).each_with_object({}) { |n, h| h[:"item_#{n}"] = 1 }
        post "/api/v1/client/dass_assessments/#{d.id}/submit",
          params: { dass_assessment: partial },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]["code"]).to eq("incomplete")
        expect(d.reload.signed?).to be(false)
      end

      it "computes scores correctly on submit" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        # All items = 1 → each subscale of 14 items sums to 14.
        post "/api/v1/client/dass_assessments/#{d.id}/submit",
          params: { dass_assessment: full_item_params(response: 1) },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        d.reload
        expect(d.depression_score).to eq(14)
        expect(d.anxiety_score).to eq(14)
        expect(d.stress_score).to eq(14)
        # severity bands per the published cutoffs:
        # depression 14 → "moderate"; anxiety 14 → "moderate";
        # stress 14 → "normal".
        expect(d.depression_severity).to eq("moderate")
        expect(d.anxiety_severity).to eq("moderate")
        expect(d.stress_severity).to eq("normal")
      end
    end
  end

  describe "Therapist surface" do
    describe "GET /api/v1/therapist/clients/:client_id/dass_assessments" do
      it "returns submitted assessments only (drafts excluded)" do
        # Two assessments: one signed, one draft.
        signed = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        (1..42).each { |n| signed["item_#{n}"] = 1 }
        signed.save!
        signed.sign!(client_user)

        DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )

        get "/api/v1/therapist/clients/#{cp.id}/dass_assessments",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["dass_assessments"].size).to eq(1)
        # Therapist DOES see raw scores (unlike client view).
        expect(body["dass_assessments"][0]).to have_key("depression_score")
      end

      it "denies an unrelated therapist" do
        other_therapist = create(:user, :therapist)
        get "/api/v1/therapist/clients/#{cp.id}/dass_assessments",
          headers: auth_header_for(other_therapist)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/therapist/clients/:client_id/dass_assessments/:id/pdf" do
      it "returns a PDF for a signed assessment" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        (1..42).each { |n| d["item_#{n}"] = 1 }
        d.save!
        d.sign!(client_user)
        get "/api/v1/therapist/clients/#{cp.id}/dass_assessments/#{d.id}/pdf",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.body[0, 5]).to eq("%PDF-")
      end

      it "404s for a draft assessment (therapist cannot see drafts)" do
        d = DassAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        get "/api/v1/therapist/clients/#{cp.id}/dass_assessments/#{d.id}/pdf",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
