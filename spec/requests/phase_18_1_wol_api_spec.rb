require "rails_helper"

RSpec.describe "Phase 18.1: Wheel of Life API", type: :request do
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:other_client) { create(:user, :client) }

  before do
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  # Helper: build a full scores hash with a uniform value across all
  # 39 items.
  def full_scores(value: 7)
    WheelOfLifeAssessment::AREAS.each_with_object({}) do |(area, count), h|
      h[area] = Array.new(count, value)
    end
  end

  describe "Client surface" do
    describe "POST /api/v1/client/wheel_of_life_assessments" do
      it "creates a draft initialized with nil items in every area" do
        post "/api/v1/client/wheel_of_life_assessments",
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        assessment = body["wheel_of_life_assessment"]
        expect(assessment["signed"]).to be(false)
        # Every area initialized as array of nils, matching AREAS counts.
        WheelOfLifeAssessment::AREAS.each do |area, count|
          expect(assessment["scores"][area]).to eq(Array.new(count))
        end
      end

      it "forbids non-clients" do
        post "/api/v1/client/wheel_of_life_assessments",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/client/wheel_of_life_assessments" do
      it "lists only the client's own assessments" do
        WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        WheelOfLifeAssessment.create!(
          client_profile: other_client.client_profile,
          author: other_client,
          assessment_date: Date.current
        )
        get "/api/v1/client/wheel_of_life_assessments",
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["wheel_of_life_assessments"].size).to eq(1)
      end
    end

    describe "PATCH /api/v1/client/wheel_of_life_assessments/:id" do
      it "merges partial area updates into existing scores" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current,
          scores: { "career" => Array.new(5),
                    "fun_and_recreation" => [10, 10, 10, 10] }
        )
        patch "/api/v1/client/wheel_of_life_assessments/#{w.id}",
          params: { wheel_of_life_assessment: {
            scores: { "career" => [9, 9, 9, 9, 9] }
          } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        w.reload
        expect(w.scores["career"]).to eq([9, 9, 9, 9, 9])
        # Other area NOT overwritten — patch only touched career.
        expect(w.scores["fun_and_recreation"]).to eq([10, 10, 10, 10])
      end

      it "accepts reflection text alongside scores" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        patch "/api/v1/client/wheel_of_life_assessments/#{w.id}",
          params: { wheel_of_life_assessment: {
            focus_area: "Career",
            current_state: "Stable but underwhelmed."
          } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        expect(w.reload.focus_area).to eq("Career")
        expect(w.current_state).to eq("Stable but underwhelmed.")
      end

      it "rejects out-of-range values via model validation" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        patch "/api/v1/client/wheel_of_life_assessments/#{w.id}",
          params: { wheel_of_life_assessment: {
            scores: { "career" => [11, 1, 1, 1, 1] }
          } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "refuses updates after signing" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current,
          scores: full_scores(value: 8)
        )
        w.sign!(client_user)
        patch "/api/v1/client/wheel_of_life_assessments/#{w.id}",
          params: { wheel_of_life_assessment: {
            scores: { "career" => [1, 1, 1, 1, 1] }
          } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]["code"]).to eq("already_signed")
      end
    end

    describe "POST /api/v1/client/wheel_of_life_assessments/:id/submit" do
      it "signs when every item across every area is filled" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        post "/api/v1/client/wheel_of_life_assessments/#{w.id}/submit",
          params: { wheel_of_life_assessment: { scores: full_scores(value: 7) } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["wheel_of_life_assessment"]["signed"]).to be(true)
      end

      it "computes per-area totals + percentages on save" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        post "/api/v1/client/wheel_of_life_assessments/#{w.id}/submit",
          params: { wheel_of_life_assessment: { scores: full_scores(value: 5) } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:ok)
        w.reload
        # Each item = 5. Career has 5 items → total 25, max 50, 50%.
        # Family has 4 items → total 20, max 40, 50%.
        expect(w.totals["career"]).to eq(
          { "total" => 25, "max" => 50, "percentage" => 50 }
        )
        expect(w.totals["family"]).to eq(
          { "total" => 20, "max" => 40, "percentage" => 50 }
        )
      end

      it "refuses incomplete submissions" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        # Only fill the career area.
        post "/api/v1/client/wheel_of_life_assessments/#{w.id}/submit",
          params: { wheel_of_life_assessment: {
            scores: { "career" => [5, 5, 5, 5, 5] }
          } },
          headers: auth_header_for(client_user)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]["code"]).to eq("incomplete")
        # Should list the unfilled items (34 of them: 39 - 5 = 34).
        expect(JSON.parse(response.body)["error"]["details"].size).to eq(34)
      end
    end
  end

  describe "Therapist surface" do
    describe "GET /api/v1/therapist/clients/:client_id/wheel_of_life_assessments" do
      it "returns submitted assessments only (drafts excluded)" do
        signed = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current,
          scores: full_scores(value: 6)
        )
        signed.sign!(client_user)

        WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )

        get "/api/v1/therapist/clients/#{cp.id}/wheel_of_life_assessments",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["wheel_of_life_assessments"].size).to eq(1)
        expect(body["wheel_of_life_assessments"][0]["signed"]).to be(true)
      end

      it "denies an unrelated therapist" do
        other_therapist = create(:user, :therapist)
        get "/api/v1/therapist/clients/#{cp.id}/wheel_of_life_assessments",
          headers: auth_header_for(other_therapist)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/therapist/clients/:client_id/wheel_of_life_assessments/:id/pdf" do
      it "returns a PDF for a signed assessment" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current,
          scores: full_scores(value: 6),
          focus_area: "Career",
          current_state: "Stable.",
          whats_missing: "Growth.",
          what_to_create: "A clearer path forward."
        )
        w.sign!(client_user)
        get "/api/v1/therapist/clients/#{cp.id}/wheel_of_life_assessments/#{w.id}/pdf",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.body[0, 5]).to eq("%PDF-")
      end

      it "404s for an unsubmitted draft" do
        w = WheelOfLifeAssessment.create!(
          client_profile: cp, author: client_user,
          assessment_date: Date.current
        )
        get "/api/v1/therapist/clients/#{cp.id}/wheel_of_life_assessments/#{w.id}/pdf",
          headers: auth_header_for(therapist)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
