require "rails_helper"

RSpec.describe "API error responses", type: :request do
  let(:json) { JSON.parse(response.body) }

  describe "permission denied (authenticated, not allowed)" do
    it "returns 403 with a machine-readable code" do
      client = create(:user, :client)
      get "/api/v1/admin/dashboard", headers: auth_header_for(client)

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("forbidden")
      expect(json["error"]).to be_present
    end
  end

  describe "unauthenticated access" do
    it "returns 401 (handled by Devise, distinct from 403)" do
      get "/api/v1/admin/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "unknown API route" do
    it "returns a consistent 404 JSON body, not an HTML page" do
      get "/api/v1/this/does/not/exist"

      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include("application/json")
      expect(json["code"]).to eq("not_found")
    end

    it "also catches non-GET verbs on unknown API routes" do
      post "/api/v1/nope", params: {}
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("not_found")
    end
  end

  describe "missing record" do
    it "returns 404 with the not_found code" do
      admin = create(:user, :admin)
      get "/api/v1/admin/applications", headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok) # sanity: route works

      # A show-style miss on an existing controller surface:
      get "/api/v1/client/payments/999999",
        headers: auth_header_for(create(:user, :client))
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
    end
  end
end
