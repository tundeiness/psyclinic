class AppointmentMailer < ApplicationMailer
  def booked(appointment)
    @appointment = appointment
    @therapist = appointment.therapist_profile
    @client = appointment.client_profile
    @slot = appointment.availability_slot
    mail(
      to: @therapist.email,
      subject: "New appointment booked with #{@client.full_name}"
    )
  end

  def reminder(appointment)
    @appointment = appointment
    @therapist = appointment.therapist_profile
    @client = appointment.client_profile
    @slot = appointment.availability_slot
    mail(
      to: @therapist.email,
      subject: "Reminder: upcoming session with #{@client.full_name}"
    )
  end
end
