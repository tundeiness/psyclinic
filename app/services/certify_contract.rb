# A therapist or admin certifies that an uploaded signed contract is
# legitimate (the signature matches, the date is valid, no obvious
# tampering). Once certified, the contract is valid_for_use and the
# client can purchase a session block.
class CertifyContract
  Result = Struct.new(:success?, :contract, :error, keyword_init: true)

  class CertifyError < StandardError; end

  def self.call(...) = new(...).call

  def initialize(contract:, certifier:)
    @contract = contract
    @certifier = certifier
  end

  def call
    unless @contract.uploaded?
      raise CertifyError,
        "Only uploaded contracts need certification."
    end
    if @contract.certified_at.present?
      raise CertifyError, "This contract is already certified."
    end
    unless @certifier.admin? || @certifier.therapist?
      raise CertifyError,
        "Only therapists or admins may certify a contract."
    end

    @contract.update!(
      certified_by_user: @certifier,
      certified_at: Time.current
    )

    # Notify the client that their contract is now valid and they
    # can proceed to buy a block.
    Notify.call(
      user: @contract.client_profile.user,
      kind: "contract_certified",
      title: "Your signed contract has been verified",
      body: "You can now purchase a session block to begin therapy.",
      subject: @contract
    )

    Result.new(success?: true, contract: @contract)
  rescue CertifyError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end
end
