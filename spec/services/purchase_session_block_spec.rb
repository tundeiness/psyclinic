require "rails_helper"

RSpec.describe PurchaseSessionBlock do
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
  end

  describe "happy path" do
    before do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
    end

    it "creates a session block + a pending payment with the full price" do
      result = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)

      expect(result.success?).to be(true)
      expect(result.session_block).to be_persisted
      expect(result.session_block.therapist_profile_id).to eq(tp.id)
      expect(result.session_block.sessions_total).to eq(6)
      expect(result.session_block.sessions_used).to eq(0)
      expect(result.session_block.payment_mode).to eq("full")
      expect(result.session_block.status).to eq("active")

      expect(result.payment).to be_persisted
      expect(result.payment.amount_cents).to eq(30_000_000)
      expect(result.payment.status).to eq("pending")
      expect(result.payment.payable).to eq(result.session_block)
      expect(result.payment.provider_reference).to be_present
      expect(result.session_block.first_payment_id).to eq(result.payment.id)
    end
  end

  describe "error cases" do
    it "rejects when the client has no current therapist" do
      expect(cp.current_therapist_id).to be_nil
      result = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(result.success?).to be(false)
      expect(result.error).to match(/assessment/i)
      expect(result.error).to match(/before buying/i)
    end

    it "rejects when the client already has an active block with sessions remaining" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
      SessionBlock.create!(
        client_profile: cp,
        therapist_profile: tp,
        purchased_at: Time.current,
        sessions_total: 6,
        sessions_used: 2,  # 4 remaining
        payment_mode: :full,
        status: :active
      )
      result = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(result.success?).to be(false)
      expect(result.error).to match(/already have an active block/i)
    end

    it "allows a new block purchase after the previous one is completed" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
      SessionBlock.create!(
        client_profile: cp,
        therapist_profile: tp,
        purchased_at: 1.day.ago,
        sessions_total: 6,
        sessions_used: 6,
        payment_mode: :full,
        status: :completed
      )
      result = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :full)
      expect(result.success?).to be(true)
    end

    it "accepts installment mode (Phase 7+) and creates a block with the 60% first payment" do
      cp.update!(current_therapist: tp)
      sign_contract_for!(cp)
      AppSetting.current.update!(block_installment_first_pct: 60,
        block_installment_second_pct: 40)
      result = PurchaseSessionBlock.call(client_profile: cp, payment_mode: :installment)
      expect(result.success?).to be(true)
      expect(result.session_block.payment_mode).to eq("installment")
      expect(result.payment.amount_cents).to eq(18_000_000)  # 60% of 30M
    end
  end
end
