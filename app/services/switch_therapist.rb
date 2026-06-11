# Phase 14: client switches their current therapist.
#
# This is a "clean break" per Cerca Africa policy and your design
# decisions:
#   - Any active session block with the previous therapist is
#     forfeited. Unused sessions are non-refundable per the contract.
#   - Any pending appointments with the previous therapist must be
#     cancelled by the client BEFORE the switch (refused here).
#   - A fresh assessment with the new therapist becomes the next
#     session (₦50,000 individually paid). After the assessment, the
#     client may buy a new block.
#   - The audit trail is captured in ClientTherapistAssignment.
#   - The prior therapist retains READ access to records they
#     authored — already enforced by Phase 1 ability rules.
#   - Notifications go to both old and new therapist.
class SwitchTherapist
  Result = Struct.new(
    :success?, :assignment, :forfeited_block, :error, :code,
    keyword_init: true
  )

  class SwitchError < StandardError
    attr_reader :code
    def initialize(message, code: :validation_failed)
      super(message)
      @code = code
    end
  end

  def self.call(...) = new(...).call

  def initialize(client_profile:, new_therapist:, reason: nil)
    @client_profile = client_profile
    @new_therapist  = new_therapist
    @reason         = reason.to_s.strip.presence
  end

  def call
    validate_inputs!

    forfeited_block = nil
    assignment = nil

    ActiveRecord::Base.transaction do
      old_therapist = @client_profile.current_therapist

      # Forfeit any active block with the OLD therapist (this is the
      # block they paid for to see that specific therapist). New
      # block must be purchased with the new therapist.
      if old_therapist
        active_block = @client_profile.session_blocks
          .where(therapist_profile_id: old_therapist.id, status: :active)
          .where("sessions_used < sessions_total")
          .lock
          .first
        if active_block
          forfeited_block = active_block
          forfeited_block.update!(status: :forfeited)
        end
      end

      # Close any currently-open assignment row.
      ClientTherapistAssignment
        .where(client_profile_id: @client_profile.id, ended_at: nil)
        .update_all(ended_at: Time.current)

      # Create the new assignment row.
      assignment = ClientTherapistAssignment.create!(
        client_profile: @client_profile,
        from_therapist: old_therapist,
        to_therapist: @new_therapist,
        started_at: Time.current,
        forfeited_block: forfeited_block,
        forfeited_sessions_count: forfeited_block&.sessions_remaining || 0,
        reason: @reason
      )

      # Repoint the client's current therapist. After this, the
      # booking flow will treat the next session with @new_therapist
      # as an assessment (first session with this therapist).
      @client_profile.update!(current_therapist: @new_therapist)

      # Notify both therapists. Wrapped in best-effort blocks so a
      # notification failure doesn't fail the switch (the switch
      # itself is the source of truth).
      notify_old_therapist(old_therapist, forfeited_block) if old_therapist
      notify_new_therapist(@new_therapist)
    end

    Result.new(
      success?: true,
      assignment: assignment,
      forfeited_block: forfeited_block
    )
  rescue SwitchError => e
    Result.new(success?: false, error: e.message, code: e.code)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message, code: :validation_failed)
  end

  private

  def validate_inputs!
    if @client_profile.current_therapist_id == @new_therapist.id
      raise SwitchError.new(
        "This is already your current therapist.",
        code: :same_therapist
      )
    end

    pending = @client_profile.appointments
      .where(status: %i[booked pending_payment])
      .joins(:availability_slot)
      .where("availability_slots.starts_at > ?", Time.current)
      .exists?
    if pending
      raise SwitchError.new(
        "You have upcoming appointments with your current therapist. " \
        "Please cancel them first, then try switching again.",
        code: :pending_appointments
      )
    end
  end

  def notify_old_therapist(old_therapist, forfeited_block)
    return unless defined?(Notify)
    body = if forfeited_block
      "Your client #{@client_profile.full_name} has chosen a new " \
        "therapist. Their block was forfeited " \
        "(#{forfeited_block.sessions_remaining} unused sessions)."
    else
      "Your client #{@client_profile.full_name} has chosen a new " \
        "therapist."
    end
    Notify.call(
      user: old_therapist.user,
      kind: "client_switched_away",
      title: "A client has switched therapists",
      body: body,
      subject: @client_profile
    )
  rescue StandardError
    # Notification is best-effort; never block the switch on it.
  end

  def notify_new_therapist(new_therapist)
    return unless defined?(Notify)
    Notify.call(
      user: new_therapist.user,
      kind: "client_chose_you",
      title: "A new client has chosen you",
      body: "#{@client_profile.full_name} would like to begin therapy " \
            "with you. Their first session will be an assessment.",
      subject: @client_profile
    )
  rescue StandardError
    # Best-effort.
  end
end
