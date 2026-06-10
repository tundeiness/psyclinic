require "rails_helper"

RSpec.describe "Block purchase end-to-end (mock checkout)", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    AppSetting.current.update!(
      block_full_price_cents: 30_000_000,
      block_installment_first_pct: 60,
      block_installment_second_pct: 40
    )
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  describe "successful block purchase" do
    it "creates block + pending payment, simulator marks them as paid" do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r.success?).to be(true)
      block, payment = r.session_block, r.payment

      # Simulate successful card on the mock checkout.
      post "/api/v1/dev/mock_gateway/#{payment.provider_reference}/simulate",
        params: { outcome: "succeed" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["payment_status"]).to eq("succeeded")
      expect(body["payable_type"]).to eq("SessionBlock")
      expect(body["session_block_id"]).to eq(block.id)

      # Block is now usable for normal-session booking.
      block.reload
      payment.reload
      expect(payment.status).to eq("succeeded")
      expect(block.status).to eq("active")
      expect(block.first_payment.succeeded?).to be(true)
    end
  end

  describe "failed block purchase" do
    it "marks the block forfeited so it can't be used" do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      block, payment = r.session_block, r.payment

      post "/api/v1/dev/mock_gateway/#{payment.provider_reference}/simulate",
        params: { outcome: "fail" }

      expect(response).to have_http_status(:ok)
      payment.reload
      block.reload
      expect(payment.status).to eq("failed")
      expect(block.status).to eq("forfeited")
      expect(block.notes).to match(/payment failed/i)
    end

    it "allows the client to retry by purchasing a new block" do
      r1 = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      post "/api/v1/dev/mock_gateway/#{r1.payment.provider_reference}/simulate",
        params: { outcome: "fail" }
      # Block is now :forfeited — should not block a new purchase.
      r2 = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(r2.success?).to be(true)
    end
  end
end
