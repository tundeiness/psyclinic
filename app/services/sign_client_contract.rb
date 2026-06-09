# Records an electronic signature on the client services contract.
# The client types their name as their signature; that, plus timestamp
# + IP, is the audit trail. No human certification needed.
#
# Validates that the typed name reasonably matches the client's name
# on file. Strict exact-match would fail on capitalization or middle-
# initial inclusion; we case-fold + strip whitespace and require the
# typed name to contain both first and last name tokens.
class SignClientContract
  Result = Struct.new(:success?, :contract, :error, keyword_init: true)

  class SignError < StandardError; end

  def self.call(...) = new(...).call

  def initialize(client_profile:, typed_name:, sponsor_name: nil,
                 sponsor_signature_typed: nil, signed_from_ip: nil)
    @client_profile = client_profile
    @typed_name = typed_name.to_s.strip
    @sponsor_name = sponsor_name.to_s.strip.presence
    @sponsor_signature_typed = sponsor_signature_typed.to_s.strip.presence
    @signed_from_ip = signed_from_ip
  end

  def call
    raise SignError, "Type your full name to sign." if @typed_name.blank?

    validate_name_match!
    validate_sponsor!

    contract = ClientContract.create!(
      client_profile: @client_profile,
      contract_version: AppSetting.current.current_contract_version,
      signature_method: :electronic,
      signed_at: Time.current,
      electronic_signature_name: @typed_name,
      signed_from_ip: @signed_from_ip,
      sponsor_name: @sponsor_name,
      sponsor_signature_typed: @sponsor_signature_typed
    )

    Result.new(success?: true, contract: contract)
  rescue SignError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

  def validate_name_match!
    on_file = @client_profile.full_name.to_s.strip
    return if on_file.blank?  # nothing to compare against

    typed_tokens = @typed_name.downcase.split(/\s+/).reject(&:blank?)
    file_tokens  = on_file.downcase.split(/\s+/).reject(&:blank?)

    # Require that every token on file appears in the typed name. This
    # lets the client add a middle name when typing if they wish, but
    # they can't sign with a wholly different name.
    missing = file_tokens - typed_tokens
    return if missing.empty?

    raise SignError,
      "The typed name doesn't match the name on your profile " \
      "(#{on_file}). Type your full legal name to sign."
  end

  def validate_sponsor!
    # If client is a minor (date_of_birth present and under 18), a
    # sponsor must sign too. We treat absence of date_of_birth as
    # "not known to be a minor" and don't enforce.
    dob = @client_profile.date_of_birth
    return unless dob

    age = ((Time.current.to_date - dob).to_i / 365.25).floor
    return if age >= 18

    if @sponsor_name.blank? || @sponsor_signature_typed.blank?
      raise SignError,
        "A sponsor must also sign — the client is a minor. Provide " \
        "both sponsor name and sponsor signature."
    end
  end
end
