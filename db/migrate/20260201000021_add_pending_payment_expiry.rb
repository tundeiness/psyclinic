class AddPendingPaymentExpiry < ActiveRecord::Migration[7.1]
  # v2 Phase 7.1: pending_payment appointments auto-expire after a
  # configurable timeout (default 30 minutes). Cleans up abandoned
  # checkout flows so slots aren't tied up indefinitely.
  #
  # Stores the timeout in app_settings so admins can tune. Records
  # expired_at on the Payment row when expiration fires, for audit.
  def change
    add_column :app_settings, :pending_payment_expiry_minutes, :integer,
      null: false, default: 30

    add_column :payments, :expired_at, :datetime
    add_index  :payments, :expired_at
  end
end
