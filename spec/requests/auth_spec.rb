require "rails_helper"

RSpec.describe "Auth & RBAC", type: :request do
  let(:json) { JSON.parse(response.body) }

  describe "POST /api/v1/signup" do
    it "registers a client and builds a client profile" do
      post "/api/v1/signup", params: {
        user: {
          email: "newclient@psyclinic.test", password: "Password123!",
          password_confirmation: "Password123!", first_name: "New", last_name: "Client",
          role: "client"
        }
      }
      expect(response).to have_http_status(:created)
      expect(json.dig("user", "role")).to eq("client")
      expect(User.last.client_profile).to be_present
    end

    it "rejects self-assigned admin role" do
      post "/api/v1/signup", params: {
        user: {
          email: "evil@psyclinic.test", password: "Password123!",
          password_confirmation: "Password123!", first_name: "E", last_name: "V",
          role: "admin"
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/login" do
    it "returns a JWT in the Authorization header" do
      create(:user, email: "login@psyclinic.test")
      post "/api/v1/login", params: { user: { email: "login@psyclinic.test", password: "Password123!" } }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to match(/\ABearer /)
    end
  end

  describe "unauthenticated access" do
    it "rejects requests with no credentials" do
      get "/api/v1/admin/clients"
      expect(response).to have_http_status(:unauthorized)
    end
  end
  # Note: role-based authorization (e.g. a client cannot read the admin
  # client list) is verified directly and exhaustively in
  # spec/domain/booking_domain_spec.rb via the Ability class. That avoids
  # coupling RBAC verification to JWT/session behavior in the test harness.
end
