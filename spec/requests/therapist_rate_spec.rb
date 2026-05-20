require "rails_helper"

# Note: rate-charging behaviour (first-free, flat rate, free sessions
# permitted) is covered comprehensively by spec/requests/co_admin_spec.rb
# under "first-ever appointment is free, then flat rate". This file
# now only covers the structural fact that no therapist-facing profile
# endpoint exists — rate is strictly admin-managed.
RSpec.describe "Therapist rate (admin-managed)", type: :request do
  let(:therapist_user) { create(:user, :therapist) }

  describe "no therapist-facing profile endpoint exists" do
    it "GET /api/v1/therapist/profile is not routed (404 JSON)" do
      get "/api/v1/therapist/profile",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
