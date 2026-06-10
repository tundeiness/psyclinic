require "rails_helper"

RSpec.describe "Client session_blocks endpoint", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }
  let(:other_client) { create(:user, :client) }

  before do
    AppSetting.current.update!(block_full_price_cents: 30_000_000)
  end

  describe "GET /api/v1/client/session_blocks" do
    it "returns the client's own blocks" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
      SessionBlock.create!(
        client_profile: cp, therapist_profile: tp,
        purchased_at: Time.current,
        sessions_total: 6, sessions_used: 2,
        payment_mode: :full, status: :active
      )

      get "/api/v1/client/session_blocks", headers: auth_header_for(client_user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_blocks"].size).to eq(1)
      expect(body["session_blocks"][0]["sessions_remaining"]).to eq(4)
      expect(body["session_blocks"][0]["therapist_name"]).to be_present
    end

    it "does not leak another client's blocks" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
      SessionBlock.create!(
        client_profile: other_client.client_profile, therapist_profile: tp,
        purchased_at: Time.current,
        sessions_total: 6, payment_mode: :full, status: :active
      )

      get "/api/v1/client/session_blocks", headers: auth_header_for(client_user)
      expect(JSON.parse(response.body)["session_blocks"]).to be_empty
    end
  end

  describe "POST /api/v1/client/session_blocks" do
    it "creates a block + payment intent on the happy path" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)

      post "/api/v1/client/session_blocks",
        params: { payment_mode: "full" },
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["session_block"]["sessions_total"]).to eq(6)
      expect(body["payment"]["amount_cents"]).to eq(30_000_000)
      expect(body["payment"]["status"]).to eq("pending")
      expect(body["payment"]["provider_reference"]).to be_present
    end

    it "returns 422 when client has no current therapist" do
      post "/api/v1/client/session_blocks",
        params: { payment_mode: "full" },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/assessment/i)
      expect(JSON.parse(response.body)["error"]).to match(/before buying/i)
    end

    it "forbids a therapist from posting" do
      post "/api/v1/client/session_blocks",
        params: { payment_mode: "full" },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
