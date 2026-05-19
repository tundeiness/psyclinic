namespace :appointments do
  desc "Send reminders for appointments starting within the next 2 days"
  task send_reminders: :environment do
    result = SendAppointmentReminders.call
    Rails.logger.info(
      "[appointments:send_reminders] reminded #{result.reminded_count} appointment(s)"
    )
    puts "[appointments:send_reminders] reminded #{result.reminded_count} appointment(s)"
  end
end
