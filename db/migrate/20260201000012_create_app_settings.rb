class CreateAppSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :app_settings do |t|
      # Practice-wide flat session rate, applied to every PAID booking.
      # The client's first-ever appointment is always free regardless.
      t.integer :flat_rate_cents, null: false, default: 0
      t.timestamps
    end
  end
end
