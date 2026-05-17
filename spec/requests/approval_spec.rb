require "rails_helper"

RSpec.describe "Account approval workflow", type: :request do
  include ActiveJob::TestHelper

  let(:json) { JSON.parse(response.body) }

  def emails = ActionMailer::Base.deliveries

  before { ActionMailer::Base.deliveries.clear }

  describe "signup creates a pending account" do
    it "registers a client as pending, notifies, and emails them" do
      perform_enqueued_jobs do
        expect {
          post "/api/v1/signup", params: {
            user: {
              email: "p1@psyclinic.test", password: "Password123!",
              password_confirmation: "Password123!",
              first_name: "Pending", last_name: "Client", role: "client"
            }
          }
        }.to change(User, :count).by(1)
      end

      expect(response).to have_http_status(:created)
      user = User.find_by(email: "p1@psyclinic.test")
      expect(user.status).to eq("pending")
      expect(user.notifications.where(kind: "application_pending")).to be_exist
      expect(emails.map(&:subject)).to include(a_string_matching(/pending/i))
    end
  end

  describe "login gating" do
    it "blocks a pending user from logging in" do
      create(:user, :pending, email: "gated@psyclinic.test")
      post "/api/v1/login",
        params: { user: { email: "gated@psyclinic.test", password: "Password123!" } }
      expect(response).to have_http_status(:unauthorized)
    end

    it "allows an approved user to log in" do
      create(:user, email: "ok@psyclinic.test") # factory default = approved
      post "/api/v1/login",
        params: { user: { email: "ok@psyclinic.test", password: "Password123!" } }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to match(/\ABearer /)
    end
  end

  describe "ApproveUser service" do
    it "approves a pending user, notifies and emails" do
      user = create(:user, :pending, :therapist)
      result = ApproveUser.call(user: user)
      expect(result.success?).to be(true)
      expect(user.reload.status).to eq("approved")
      expect(user.notifications.where(kind: "application_approved")).to be_exist
    end

    it "is a no-op on an already-approved user" do
      user = create(:user) # approved
      result = ApproveUser.call(user: user)
      expect(result.success?).to be(true)
      expect(user.reload.status).to eq("approved")
    end

    it "refuses to approve an admin" do
      admin = create(:user, :admin)
      result = ApproveUser.call(user: admin)
      expect(result.success?).to be(false)
    end
  end

  describe "RejectUser service" do
    it "rejects a pending user and notifies" do
      user = create(:user, :pending)
      result = RejectUser.call(user: user)
      expect(result.success?).to be(true)
      expect(user.reload.status).to eq("rejected")
      expect(user.notifications.where(kind: "application_rejected")).to be_exist
    end
  end

  describe "admin applications endpoint authorization" do
    it "lets an admin list pending applications" do
      create(:user, :pending, email: "a@psyclinic.test")
      admin = create(:user, :admin)
      get "/api/v1/admin/applications", headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(json["applications"].map { |a| a["email"] }).to include("a@psyclinic.test")
    end
  end
end
