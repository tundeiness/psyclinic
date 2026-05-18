# Finds confirmed (booked) appointments whose session starts within the
# reminder window (default: between now and 2 days out) and that have not
# already been reminded, then notifies + emails the therapist. Idempotent
# via appointments.reminder_sent_at, so running it repeatedly (e.g. every
# hour from a scheduler) will not double-send.
class SendAppointmentReminders
  Result = Struct.new(:reminded_count, keyword_init: true)

  DEFAULT_WINDOW = 2.days

  def self.call(...) = new(...).call

  def initialize(within: DEFAULT_WINDOW, now: Time.current)
    @within = within
    @now = now
  end

  def call
    cutoff = @now + @within

    appointments = Appointment
      .where(status: :booked)
      .where(reminder_sent_at: nil)
      .joins(:availability_slot)
      .where(availability_slots: { starts_at: @now..cutoff })
      .includes(:therapist_profile, :client_profile, :availability_slot)

    count = 0
    appointments.find_each do |appt|
      send_reminder(appt)
      appt.update_columns(reminder_sent_at: Time.current)
      count += 1
    end

    Result.new(reminded_count: count)
  end

  private

  def send_reminder(appt)
    therapist_user = appt.therapist_profile.user
    Notify.call(
      user: therapist_user,
      kind: "appointment_reminder",
      title: "Upcoming appointment reminder",
      body: "You have a session with #{appt.client_profile.full_name} soon.",
      subject: appt
    )
    AppointmentMailer.reminder(appt).deliver_later
  end
end
