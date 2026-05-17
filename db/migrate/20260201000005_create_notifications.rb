class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }

      # e.g. "application_pending", "application_approved",
      # "application_rejected", "appointment_booked",
      # "appointment_reminder", "payment_received"
      t.string :kind, null: false
      t.string :title, null: false
      t.text   :body

      # Optional loose link back to a record (no polymorphic FK to keep
      # it simple): e.g. "Appointment", 42
      t.string  :subject_type
      t.bigint  :subject_id

      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, %i[user_id read_at]
    add_index :notifications, %i[subject_type subject_id]
  end
end
