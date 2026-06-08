require "rails_helper"

RSpec.describe "Admin settings endpoint (v2 pricing)", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:therapist)     { create(:user, :therapist) }
  let(:client_user)   { create(:user, :client) }

  describe "GET /api/v1/admin/settings" do
    it "returns the v2 pricing keys + computed installment amounts" do
      AppSetting.current  # ensure row exists with defaults

      get "/api/v1/admin/settings", headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      s = body.fetch("settings")
      expect(s["assessment_session_price_cents"]).to eq(5_000_000)
      expect(s["block_full_price_cents"]).to eq(30_000_000)
      expect(s["block_installment_first_pct"]).to eq(60)
      expect(s["block_installment_second_pct"]).to eq(40)
      expect(s["installment_first_amount_cents"]).to eq(18_000_000)
      expect(s["installment_second_amount_cents"]).to eq(12_000_000)
    end
  end

  describe "PATCH /api/v1/admin/settings" do
    it "updates v2 pricing fields" do
      patch "/api/v1/admin/settings",
        params: { settings: {
          assessment_session_price_cents: 6_000_000,
          block_full_price_cents: 36_000_000
        } },
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)

      s = AppSetting.current
      expect(s.assessment_session_price_cents).to eq(6_000_000)
      expect(s.block_full_price_cents).to eq(36_000_000)
    end

    it "rejects installment pcts that don't sum to 100" do
      patch "/api/v1/admin/settings",
        params: { settings: {
          block_installment_first_pct: 70,
          block_installment_second_pct: 40
        } },
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).fetch("details").join).to match(/sum to 100/)
    end

    it "forbids a non-admin therapist from changing pricing" do
      patch "/api/v1/admin/settings",
        params: { settings: { assessment_session_price_cents: 1 } },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids the client" do
      patch "/api/v1/admin/settings",
        params: { settings: { assessment_session_price_cents: 1 } },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
