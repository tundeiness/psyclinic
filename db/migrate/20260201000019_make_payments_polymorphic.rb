class MakePaymentsPolymorphic < ActiveRecord::Migration[7.1]
  # v2: Payments can now attach to either an Appointment (legacy +
  # assessment session payments) or a SessionBlock (block-purchase
  # payments). Adds polymorphic columns, backfills existing rows,
  # and relaxes the appointment_id constraints so block-only
  # payments can have it null.
  #
  # Strategy: keep appointment_id around for one phase as a fallback,
  # so any code that still reads payment.appointment_id keeps working
  # while we migrate callers. Drop in a later phase once nothing
  # depends on it.
  def up
    # 1. Add the polymorphic columns nullable so the backfill can run
    #    before we tighten constraints.
    add_column :payments, :payable_type, :string
    add_column :payments, :payable_id,   :bigint

    # 2. Backfill existing rows. SQL update is faster than iterating
    #    AR records, especially as payment count grows.
    execute <<~SQL.squish
      UPDATE payments
      SET payable_type = 'Appointment',
          payable_id   = appointment_id
      WHERE appointment_id IS NOT NULL
    SQL

    # 3. Now tighten the polymorphic columns.
    change_column_null :payments, :payable_type, false
    change_column_null :payments, :payable_id,   false

    # 4. Loosen the legacy column. appointment_id stays as a fallback
    #    that the Payment model reads via the polymorphic association,
    #    but new block-payment rows will have appointment_id == NULL.
    change_column_null :payments, :appointment_id, true

    # 5. Drop the uniqueness on appointment_id — block payments don't
    #    even have an appointment_id, but more importantly the legacy
    #    appointment_id column will eventually go away. Replace with a
    #    composite unique index on (payable_type, payable_id) so each
    #    appointment / block has at most one payment row.
    remove_index :payments, :appointment_id
    add_index    :payments, :appointment_id  # non-unique replacement

    add_index :payments, [:payable_type, :payable_id],
      unique: true,
      name: "idx_unique_payment_per_payable"
  end

  def down
    remove_index :payments, name: "idx_unique_payment_per_payable"
    remove_index :payments, :appointment_id
    add_index    :payments, :appointment_id, unique: true

    change_column_null :payments, :appointment_id, false

    remove_column :payments, :payable_id
    remove_column :payments, :payable_type
  end
end
