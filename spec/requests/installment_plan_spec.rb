require "rails_helper"

RSpec.describe "Installment plan (60/40)", type: :request do
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

  def make_slot(starts: 2.days.from_now)
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: starts,
      ends_at: starts + 1.hour,
      status: :approved
    )
  end

  describe "purchasing an installment block" do
    it "creates a block in installment mode + first payment of 60%" do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :installment)
      expect(r.success?).to be(true)
      expect(r.session_block.payment_mode).to eq("installment")
      expect(r.payment.amount_cents).to eq(18_000_000)  # 60% of 30,000,000
    end

    it "the block becomes usable once the first installment succeeds" do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :installment)
      post "/api/v1/dev/mock_gateway/#{r.payment.provider_reference}/simulate",
        params: { outcome: "succeed" }
      expect(r.session_block.reload.first_payment.succeeded?).to be(true)
    end
  end

  describe "session-3 threshold gating" do
    let(:block) do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :installment)
      post "/api/v1/dev/mock_gateway/#{r.payment.provider_reference}/simulate",
        params: { outcome: "succeed" }
      r.session_block.reload
    end

    it "allows booking sessions 1-3 normally" do
      block  # ensure first payment succeeded
      3.times do |i|
        slot = make_slot(starts: (3 + i).days.from_now)
        result = BookAppointment.call(
          client_profile: cp,
          availability_slot_id: slot.id,
          session_kind: :normal
        )
        expect(result.success?).to be(true)
      end
      expect(block.reload.sessions_used).to eq(3)
      expect(block.installment_due?).to be(true)
    end

    it "rejects booking the 4th session until the 40% is paid" do
      block.update!(sessions_used: 3)
      expect(block.installment_due?).to be(true)

      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/installment/i)
      expect(result.error).to match(/40%/)
    end
  end

  describe "paying the second installment" do
    let(:block) do
      r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :installment)
      post "/api/v1/dev/mock_gateway/#{r.payment.provider_reference}/simulate",
        params: { outcome: "succeed" }
      r.session_block.reload.tap { |b| b.update!(sessions_used: 3) }
    end

    it "creates a second payment and intent at the right amount" do
      block  # set up
      post "/api/v1/client/session_blocks/#{block.id}/pay_installment",
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["payment"]["amount_cents"]).to eq(12_000_000)
      expect(body["payment"]["status"]).to eq("pending")
      expect(body["payment"]["provider_reference"]).to be_present

      block.reload
      expect(block.second_payment_id).to be_present
    end

    it "allows booking session 4 once the second payment succeeds" do
      post "/api/v1/client/session_blocks/#{block.id}/pay_installment",
        headers: auth_header_for(client_user)
      intent = JSON.parse(response.body).dig("payment", "provider_reference")

      post "/api/v1/dev/mock_gateway/#{intent}/simulate",
        params: { outcome: "succeed" }

      expect(block.reload.installment_due?).to be(false)

      slot = make_slot
      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :normal
      )
      expect(result.success?).to be(true)
    end

    it "clears second_payment_id and stays active if the second payment fails" do
      post "/api/v1/client/session_blocks/#{block.id}/pay_installment",
        headers: auth_header_for(client_user)
      intent = JSON.parse(response.body).dig("payment", "provider_reference")

      post "/api/v1/dev/mock_gateway/#{intent}/simulate",
        params: { outcome: "fail" }

      block.reload
      # Block remains active (not forfeited) — client just needs to retry.
      expect(block.status).to eq("active")
      # second_payment_id was cleared so the client can re-initiate.
      expect(block.second_payment_id).to be_nil
      expect(block.installment_due?).to be(true)
    end

    it "rejects pay_installment when second payment already succeeded" do
      post "/api/v1/client/session_blocks/#{block.id}/pay_installment",
        headers: auth_header_for(client_user)
      intent = JSON.parse(response.body).dig("payment", "provider_reference")
      post "/api/v1/dev/mock_gateway/#{intent}/simulate",
        params: { outcome: "succeed" }

      post "/api/v1/client/session_blocks/#{block.id}/pay_installment",
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/already paid/i)
    end

    it "rejects pay_installment on a non-installment block" do
      full_r = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      post "/api/v1/client/session_blocks/#{full_r.session_block.id}/pay_installment",
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/not purchased on an installment/i)
    end
  end
end
