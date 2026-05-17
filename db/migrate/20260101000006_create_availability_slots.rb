class CreateAvailabilitySlots < ActiveRecord::Migration[7.1]
  def change
    create_table :availability_slots do |t|
      t.references :therapist_profile, null: false, foreign_key: { on_delete: :cascade }

      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      # 0 = proposed (therapist created), 1 = approved (admin OK'd),
      # 2 = rejected. Only approved slots are bookable.
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :availability_slots, %i[therapist_profile_id starts_at]
    add_index :availability_slots, :status

    # Prevent a therapist from having two slots with the exact same start.
    add_index :availability_slots,
      %i[therapist_profile_id starts_at ends_at],
      unique: true,
      name: "idx_unique_slot_per_therapist"

    # End must be strictly after start.
    add_check_constraint :availability_slots,
      "ends_at > starts_at",
      name: "chk_slot_time_order"
  end
end
