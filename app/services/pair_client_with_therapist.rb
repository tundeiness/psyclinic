# Encapsulates the admin action of pairing a client to a therapist.
# Returns a Result so controllers stay thin.
class PairClientWithTherapist
  Result = Struct.new(:success?, :client_profile, :error, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(client_profile:, therapist_profile:)
    @client_profile = client_profile
    @therapist_profile = therapist_profile
  end

  def call
    if @therapist_profile.nil? || !@therapist_profile.active?
      return Result.new(success?: false, error: "Therapist is not available for pairing")
    end

    @client_profile.therapist_profile = @therapist_profile

    if @client_profile.save
      Result.new(success?: true, client_profile: @client_profile)
    else
      Result.new(success?: false, error: @client_profile.errors.full_messages.to_sentence)
    end
  end
end
