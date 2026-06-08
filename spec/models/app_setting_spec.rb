require "rails_helper"

RSpec.describe AppSetting, type: :model do
  describe "v2 pricing defaults" do
    it "uses sensible defaults from the design doc" do
      s = AppSetting.create!(flat_rate_cents: 0)
      expect(s.assessment_session_price_cents).to eq(5_000_000)   # ₦50,000
      expect(s.block_full_price_cents).to eq(30_000_000)          # ₦300,000
      expect(s.block_installment_first_pct).to eq(60)
      expect(s.block_installment_second_pct).to eq(40)
    end
  end

  describe "installment math" do
    let(:s) {
      AppSetting.create!(
        flat_rate_cents: 0,
        block_full_price_cents: 30_000_000,
        block_installment_first_pct: 60,
        block_installment_second_pct: 40
      )
    }

    it "first installment is 60% of the block" do
      expect(s.installment_first_amount_cents).to eq(18_000_000)
    end

    it "second installment is 40% of the block" do
      expect(s.installment_second_amount_cents).to eq(12_000_000)
    end

    it "first + second always equals the full price (no rounding gap)" do
      s.update!(block_full_price_cents: 30_000_001) # awkward odd number
      total = s.installment_first_amount_cents + s.installment_second_amount_cents
      expect(total).to eq(30_000_001)
    end
  end

  describe "validations" do
    it "rejects negative prices" do
      s = AppSetting.new(
        flat_rate_cents: 0,
        assessment_session_price_cents: -1
      )
      expect(s.valid?).to be(false)
    end

    it "rejects percentages outside 0-100" do
      s = AppSetting.new(
        flat_rate_cents: 0,
        block_installment_first_pct: 150,
        block_installment_second_pct: 0
      )
      expect(s.valid?).to be(false)
    end

    it "rejects installment percentages that don't sum to 100" do
      s = AppSetting.new(
        flat_rate_cents: 0,
        block_installment_first_pct: 70,
        block_installment_second_pct: 40
      )
      expect(s.valid?).to be(false)
      expect(s.errors[:base].join).to match(/sum to 100/)
    end
  end
end
