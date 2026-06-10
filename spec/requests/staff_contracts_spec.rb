require "rails_helper"

RSpec.describe "Staff contracts certification", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:therapist) { create(:user, :therapist) }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile.tap { |c| c.update!(date_of_birth: 25.years.ago) } }

  before do
    AppSetting.current.update!(current_contract_version: "v1-2026")
    cp.update!(current_therapist: therapist.therapist_profile)
  end

  def make_upload!
    contract = ClientContract.new(
      client_profile: cp,
      contract_version: "v1-2026",
      signature_method: :uploaded,
      signed_at: Time.current
    )
    contract.uploaded_document.attach(
      io: StringIO.new("%PDF-1.4 fake bytes"),
      filename: "signed.pdf",
      content_type: "application/pdf"
    )
    contract.save!
    contract
  end

  describe "GET /api/v1/staff/contracts/pending" do
    it "lists uploaded contracts awaiting certification" do
      make_upload!
      get "/api/v1/staff/contracts/pending", headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["contracts"].size).to eq(1)
      expect(body["contracts"][0]["client_name"]).to eq(cp.full_name)
      expect(body["contracts"][0]["pending_certification"]).to be(true)
    end

    it "is accessible to therapists too" do
      make_upload!
      get "/api/v1/staff/contracts/pending", headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
    end

    it "forbids unauthenticated access" do
      get "/api/v1/staff/contracts/pending"
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it "forbids clients" do
      get "/api/v1/staff/contracts/pending", headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/staff/contracts/:id/certify" do
    it "marks an uploaded contract as certified" do
      c = make_upload!
      post "/api/v1/staff/contracts/#{c.id}/certify",
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      c.reload
      expect(c.certified_at).to be_present
      expect(c.certified_by_user_id).to eq(admin.id)
      expect(c.valid_for_use?).to be(true)
    end

    it "rejects certifying twice" do
      c = make_upload!
      post "/api/v1/staff/contracts/#{c.id}/certify", headers: auth_header_for(admin)
      post "/api/v1/staff/contracts/#{c.id}/certify", headers: auth_header_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/already certified/i)
    end

    it "rejects certifying an electronic contract" do
      c = SignClientContract.call(client_profile: cp, typed_name: cp.full_name).contract
      post "/api/v1/staff/contracts/#{c.id}/certify", headers: auth_header_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/only uploaded/i)
    end
  end
end
