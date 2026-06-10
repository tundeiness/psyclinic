# Phase 12: client no-show tracking.
#
# Finds :booked appointments whose slot ended more than 1 hour ago and
# transitions them to :no_show. The 1-hour grace gives the therapist
# time to mark :completed first — if they don't, the system flips it
# automatically per Cerca Africa's policy ("Failure to show up for a
# session without required notice will make the session count as
# held").
#
# Important: :no_show is in RESERVING_STATUSES, so the slot stays
# reserved — the session counted as held, the block was already
# decremented at booking time. No refund, no slot re-release.
#
# Called from the therapist appointments-list controller and from
# admin views. Idempotent and safe to call any number of times.
class SweepNoShows
  Result = Struct.new(:marked_count, keyword_init: true)

  # Grace period after the slot's end_time before we'll auto-flip
  # an unmarked appointment. Therapists get this much time to mark
  # it :completed themselves.
  GRACE_PERIOD = 1.hour

  def self.call(therapist_profile: nil, client_profile: nil)
    new(therapist_profile: therapist_profile,
        client_profile: client_profile).call
  end

  def initialize(therapist_profile: nil, client_profile: nil)
    @therapist_profile = therapist_profile
    @client_profile = client_profile
  end

  def call
    cutoff = Time.current - GRACE_PERIOD

    scope = Appointment
      .where(status: :booked)
      .joins(:availability_slot)
      .where("availability_slots.ends_at < ?", cutoff)

    scope = scope.where(therapist_profile_id: @therapist_profile.id) if @therapist_profile
    scope = scope.where(client_profile_id: @client_profile.id)       if @client_profile

    count = 0
    scope.find_each do |appt|
      next unless mark_one(appt)
      count += 1
    end

    Result.new(marked_count: count)
  end

  private

  # Returns true if WE were the ones who flipped it. Re-checks state
  # after acquiring a record-level lock so we don't race with a
  # therapist manually updating to :completed in the same window.
  def mark_one(appt)
    flipped = false
    ActiveRecord::Base.transaction do
      appt.lock!
      appt.reload

      if appt.booked?
        appt.update!(status: :no_show, no_show_marked_at: Time.current)
        flipped = true
      end
    end
    flipped
  end
end
