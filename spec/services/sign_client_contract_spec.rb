require "rails_helper"

RSpec.describe SignClientContract do
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    cp.update!(date_of_birth: 25.years.ago)
    AppSetting.current.update!(current_contract_version: "v1-2026")
  end

  describe "happy path" do
    it "creates an electronic contract for a matching name" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: cp.full_name,
        signed_from_ip: "1.2.3.4"
      )
      expect(result.success?).to be(true)
      expect(result.contract).to be_persisted
      expect(result.contract.electronic?).to be(true)
      expect(result.contract.electronic_signature_name).to eq(cp.full_name)
      expect(result.contract.signed_from_ip).to eq("1.2.3.4")
      expect(result.contract.contract_version).to eq("v1-2026")
      expect(result.contract.valid_for_use?).to be(true)
    end

    it "accepts a typed name with an added middle name" do
      typed = "#{cp.user.first_name} Q. #{cp.user.last_name}"
      result = SignClientContract.call(client_profile: cp, typed_name: typed)
      expect(result.success?).to be(true)
    end

    it "case-insensitive match" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: cp.full_name.upcase
      )
      expect(result.success?).to be(true)
    end
  end

  describe "validation" do
    it "rejects an empty typed name" do
      result = SignClientContract.call(client_profile: cp, typed_name: "")
      expect(result.success?).to be(false)
      expect(result.error).to match(/type your full name/i)
    end

    it "rejects a typed name missing the last name" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: cp.user.first_name
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/doesn't match/i)
    end

    it "rejects an unrelated name" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: "Some Otherperson"
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/doesn't match/i)
    end
  end

  describe "minor sponsor requirement" do
    before { cp.update!(date_of_birth: 10.years.ago) }

    it "rejects when no sponsor is given" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: cp.full_name
      )
      expect(result.success?).to be(false)
      expect(result.error).to match(/sponsor must also sign/i)
    end

    it "accepts when both sponsor fields are given" do
      result = SignClientContract.call(
        client_profile: cp,
        typed_name: cp.full_name,
        sponsor_name: "Parent Name",
        sponsor_signature_typed: "Parent Name"
      )
      expect(result.success?).to be(true)
      expect(result.contract.sponsor_name).to eq("Parent Name")
    end
  end
end
