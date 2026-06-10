class SessionBlock < ApplicationRecord
  belongs_to :client_profile
  belongs_to :therapist_profile

  # Payments are added in Phase 5 when the polymorphic Payment refactor
  # lands. For now these are just nullable FKs.
  belongs_to :first_payment,  class_name: "Payment", optional: true
  belongs_to :second_payment, class_name: "Payment", optional: true

  # v2: a SessionBlock is a payable — Payment.payable_type = "SessionBlock".
  # has_many because installment-mode blocks have TWO payments (60% +
  # 40%). For full-pay blocks, only one Payment row exists. Prefer the
  # explicit first_payment / second_payment accessors when you want
  # one specific row.
  has_many :payments, as: :payable, dependent: :destroy

  has_many :appointments, dependent: :nullify

  enum :payment_mode, { full: 0, installment: 1 }, default: :full
  enum :status,
    { active: 0, completed: 1, refunded: 2, forfeited: 3, expired: 4 },
    default: :active

  validates :sessions_total,
    numericality: { greater_than: 0, only_integer: true }
  validates :sessions_used,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :sessions_used_within_total
  validates :purchased_at, presence: true

  # Phase 13: 6-week block expiry per Cerca Africa policy
  # ("Unattended sessions expire 6 weeks after the last session
  # attended").
  EXPIRY_WINDOW = 6.weeks

  # True once the client has consumed 3 sessions in an installment-mode
  # block AND the second-installment payment has not yet succeeded.
  # Used by the booking flow (Phase 7+) to gate session 4+ behind
  # paying the 40% remainder.
  def installment_due?
    return false unless installment?
    return false if sessions_used < 3
    return true if second_payment_id.nil?
    # A second_payment row exists but is still pending or failed —
    # not yet "paid." Treat as still due so the client gets the nag
    # to complete it.
    !second_payment&.succeeded?
  end

  def sessions_remaining
    sessions_total - sessions_used
  end

  # Phase 13: the slot.starts_at of the most recent held session
  # (completed or no_show — both "count as held" per policy and
  # Phase 12). Returns nil if no session has been held yet.
  def last_held_at
    appointments
      .joins(:availability_slot)
      .where(status: %w[completed no_show])
      .order("availability_slots.starts_at DESC")
      .limit(1)
      .pick("availability_slots.starts_at")
  end

  # Phase 13: when does this block expire? 6 weeks after the most
  # recent held session, or 6 weeks after the first payment was
  # received if no session has been held yet. Returns nil only when
  # we have no anchor at all (shouldn't happen in practice — a usable
  # block always has a first_payment.paid_at).
  def expires_at
    anchor = last_held_at || first_payment&.paid_at || purchased_at
    return nil if anchor.nil?
    anchor + EXPIRY_WINDOW
  end

  def expired?
    e = expires_at
    return false if e.nil?
    e < Time.current
  end

  # True when the block is currently active AND has unused sessions
  # AND has not expired. This is the precise "can I draw a session
  # from this block right now?" check used by BookAppointment.
  def usable?
    active? && sessions_remaining > 0 && !expired?
  end

  private

  def sessions_used_within_total
    return if sessions_used.to_i <= sessions_total.to_i
    errors.add(:sessions_used,
      "cannot exceed sessions_total (#{sessions_total})")
  end
end
