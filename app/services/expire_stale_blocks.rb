# Phase 13: 6-week block expiry.
#
# Finds :active SessionBlocks whose expiry window has elapsed
# (per the model's SessionBlock#expired? method) and flips them
# to :expired. Sessions still in the block are forfeit per Cerca
# Africa policy: "Unattended sessions expire 6 weeks after the
# last attended session."
#
# Called from client + therapist appointment-list reads (same
# pattern as SweepNoShows). Idempotent.
#
# Note: we compute expired? in Ruby rather than pushing it into a
# SQL WHERE because the expiry anchor depends on the last held
# appointment (a join against appointments + slots) which makes
# the SQL ugly. The active-block set is small (one per client)
# so iterating is fine.
class ExpireStaleBlocks
  Result = Struct.new(:expired_count, keyword_init: true)

  def self.call(client_profile: nil)
    new(client_profile: client_profile).call
  end

  def initialize(client_profile: nil)
    @client_profile = client_profile
  end

  def call
    scope = SessionBlock.where(status: :active)
    scope = scope.where(client_profile_id: @client_profile.id) if @client_profile

    count = 0
    scope.find_each do |block|
      next unless block.expired?
      next unless mark_one(block)
      count += 1
    end

    Result.new(expired_count: count)
  end

  private

  # Acquire a row lock and re-check before flipping — defends against
  # racing with a concurrent booking that just consumed a session
  # (which would also reset the expiry clock).
  def mark_one(block)
    flipped = false
    ActiveRecord::Base.transaction do
      block.lock!
      block.reload
      if block.active? && block.expired?
        block.update!(status: :expired)
        flipped = true
      end
    end
    flipped
  end
end
