require "rails_helper"

RSpec.describe "Client contracts endpoint", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile.tap { |c| c.update!(date_of_birth: 25.years.ago) } }

  before do
    AppSetting.current.update!(
      current_contract_version: "v1-2026",
      block_full_price_cents: 30_000_000
    )
    cp.update!(current_therapist: tp)
  end

  describe "GET /api/v1/client/contracts/current" do
    it "reports requires_signing=true when no contract exists" do
      get "/api/v1/client/contracts/current", headers: auth_header_for(client_user)
      body = JSON.parse(response.body)
      expect(body["current_version"]).to eq("v1-2026")
      expect(body["requires_signing"]).to be(true)
      expect(body["signed_contract"]).to be_nil
    end

    it "reports the signed contract once one exists" do
      SignClientContract.call(client_profile: cp, typed_name: cp.full_name)
      get "/api/v1/client/contracts/current", headers: auth_header_for(client_user)
      body = JSON.parse(response.body)
      expect(body["requires_signing"]).to be(false)
      expect(body["signed_contract"]["valid_for_use"]).to be(true)
    end
  end

  describe "GET /api/v1/client/contracts/document" do
    it "streams a PDF" do
      get "/api/v1/client/contracts/document", headers: auth_header_for(client_user)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("application/pdf")
      expect(response.body[0, 4]).to eq("%PDF")
    end
  end

  describe "POST /api/v1/client/contracts/sign" do
    it "creates an electronic contract" do
      post "/api/v1/client/contracts/sign",
        params: { typed_name: cp.full_name },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["contract"]["signature_method"]).to eq("electronic")
      expect(body["contract"]["valid_for_use"]).to be(true)
    end

    it "rejects a name mismatch" do
      post "/api/v1/client/contracts/sign",
        params: { typed_name: "Different Person" },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "Block purchase gate" do
    it "rejects PurchaseSessionBlock without a signed contract" do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r.success?).to be(false)
      expect(r.error).to match(/sign the client services contract/i)
    end

    it "allows PurchaseSessionBlock once electronically signed" do
      SignClientContract.call(client_profile: cp, typed_name: cp.full_name)
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r.success?).to be(true)
    end

    it "rejects an uploaded contract that hasn't been certified yet" do
      ClientContract.create!(
        client_profile: cp,
        contract_version: "v1-2026",
        signature_method: :uploaded,
        signed_at: Time.current
      ).tap do |c|
        c.uploaded_document.attach(
          io: StringIO.new("fake pdf bytes"),
          filename: "test.pdf",
          content_type: "application/pdf"
        )
        c.save!
      end
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r.success?).to be(false)
      expect(r.error).to match(/sign the client services contract/i)
    end

    it "rejects when current required version changes (forces re-sign)" do
      SignClientContract.call(client_profile: cp, typed_name: cp.full_name)
      AppSetting.current.update!(current_contract_version: "v2-2027")
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r.success?).to be(false)
    end
  end
end
