class AddReminderSentAtToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :reminder_sent_at, :datetime
    add_index  :appointments, :reminder_sent_at
  end
end
