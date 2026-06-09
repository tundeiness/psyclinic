# Finds pending_payment appointments older than the configured
# timeout (AppSetting.pending_payment_expiry_minutes, default 30) and
# expires them: appointment -> :cancelled, payment -> :failed, payment
# expired_at -> Time.current.
#
# Idempotent and safe to call as often as desired. Called from:
#  - BookAppointment (before creating a new appointment for a client,
#    we sweep any of THEIR stale ones so old reservations don't
#    interfere)
#  - Client::AvailabilitySlotsController (so slots blocked by stale
#    reservations show as available again to OTHER clients)
#  - Client::AppointmentsController (so the client's own list reflects
#    reality)
#
# Race-safe via row-level locking on the payment when transitioning,
# in case a real webhook arrives in the same millisecond. ConfirmPayment
# also guards against acting on an already-expired payment.
class ExpireStalePayments
  Result = Struct.new(:expired_count, keyword_init: true)

  def self.call(client_profile: nil)
    new(client_profile: client_profile).call
  end

  def initialize(client_profile: nil)
    @client_profile = client_profile
  end

  def call
    cutoff = cutoff_time
    scope = Appointment
      .where(status: :pending_payment)
      .where("appointments.created_at < ?", cutoff)
      .includes(:payment)

    scope = scope.where(client_profile_id: @client_profile.id) if @client_profile

    count = 0
    scope.find_each do |appt|
      next unless expire_one(appt)
      count += 1
    end

    Result.new(expired_count: count)
  end

  private

  def cutoff_time
    minutes = AppSetting.current.pending_payment_expiry_minutes.to_i
    minutes = 30 if minutes <= 0  # safety net
    minutes.minutes.ago
  end

  # Returns true if this appointment was actually expired by us
  # (false if a concurrent transition already moved it). The
  # row-level lock on the payment ensures we don't race with
  # ConfirmPayment in the (very narrow) window where a webhook
  # arrives at exactly the timeout moment.
  def expire_one(appt)
    payment = appt.payment
    return false if payment.nil?

    expired = false
    ActiveRecord::Base.transaction do
      payment.lock!  # serialize with ConfirmPayment / other expirers

      # Re-check after locking: state may have changed concurrently.
      payment.reload
      appt.reload

      if payment.pending? && appt.pending_payment?
        payment.update!(status: :failed, expired_at: Time.current)
        appt.update!(status: :cancelled)
        expired = true
      end
    end
    expired
  end
end
