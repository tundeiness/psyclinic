class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :appointment, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }

      t.integer :amount_cents, null: false, default: 0
      t.string  :currency, null: false, default: "USD"

      # 0 = pending, 1 = succeeded, 2 = failed, 3 = refunded
      t.integer :status, null: false, default: 0

      # Gateway-agnostic: which provider handled it and its reference id.
      # Null until a real gateway is wired (stubbed for now).
      t.string :provider
      t.string :provider_reference
      t.jsonb  :provider_payload, null: false, default: {}

      t.datetime :paid_at

      t.timestamps
    end

    add_index :payments, :status
    add_index :payments, :provider_reference
    add_check_constraint :payments, "amount_cents >= 0",
      name: "chk_payment_amount_non_negative"
  end
end
