class RedefineActiveAppointmentIndexForPayments < ActiveRecord::Migration[7.1]
  # Appointment statuses (integers preserved to protect existing rows):
  #   0 booked, 1 completed, 2 cancelled,
  #   3 pending_payment (added), 4 payment_failed (added)
  #
  # A slot is "occupied" while an appointment is booked/completed/
  # pending_payment. It is RELEASED when cancelled (2) or payment_failed
  # (4). The old index used `status <> 2`; that would keep a slot locked
  # after a failed payment. Redefine it to exclude both 2 and 4.
  def up
    remove_index :appointments, name: "idx_one_active_appointment_per_slot"
    add_index :appointments, :availability_slot_id,
      unique: true,
      where: "status NOT IN (2, 4)",
      name: "idx_one_active_appointment_per_slot"
  end

  def down
    remove_index :appointments, name: "idx_one_active_appointment_per_slot"
    add_index :appointments, :availability_slot_id,
      unique: true,
      where: "status <> 2",
      name: "idx_one_active_appointment_per_slot"
  end
end
