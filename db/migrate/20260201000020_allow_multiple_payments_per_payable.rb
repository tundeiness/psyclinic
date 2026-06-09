class AllowMultiplePaymentsPerPayable < ActiveRecord::Migration[7.1]
  # v2 Phase 7: installment-mode blocks have TWO payments per block
  # (60% up-front + 40% after 3 sessions). The unique index from the
  # polymorphic migration is too strict — replace with a non-unique
  # index that still helps lookup performance.
  #
  # For appointments, uniqueness is still desired (one payment per
  # appointment). That's enforced separately by the legacy
  # `appointments.id` unique-when-not-null partial index pattern,
  # but for safety we add a partial unique index on
  # (payable_type, payable_id) WHERE payable_type='Appointment'.
  def up
    remove_index :payments, name: "idx_unique_payment_per_payable"
    add_index :payments, [:payable_type, :payable_id],
      name: "idx_payments_on_payable"

    # Partial unique: at most one payment per Appointment.
    # SessionBlock payments are exempt — they can have multiple
    # (first + second installment).
    add_index :payments, [:payable_type, :payable_id],
      unique: true,
      where: "payable_type = 'Appointment'",
      name: "idx_unique_payment_per_appointment_payable"
  end

  def down
    remove_index :payments, name: "idx_unique_payment_per_appointment_payable"
    remove_index :payments, name: "idx_payments_on_payable"
    add_index :payments, [:payable_type, :payable_id],
      unique: true,
      name: "idx_unique_payment_per_payable"
  end
end
