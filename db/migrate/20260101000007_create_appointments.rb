class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :appointments do |t|
      t.references :client_profile, null: false, foreign_key: { on_delete: :cascade }
      t.references :therapist_profile, null: false, foreign_key: { on_delete: :cascade }
      t.references :availability_slot, null: false, foreign_key: { on_delete: :cascade }

      # 0 = booked, 1 = completed, 2 = cancelled
      t.integer :status, null: false, default: 0
      t.text :reason

      t.timestamps
    end

    # A slot can be booked at most once by a non-cancelled appointment.
    # Partial unique index: enforced only while status <> 2 (cancelled).
    add_index :appointments,
      :availability_slot_id,
      unique: true,
      where: "status <> 2",
      name: "idx_one_active_appointment_per_slot"

    add_index :appointments, %i[client_profile_id status]
    add_index :appointments, %i[therapist_profile_id status]
  end
end
