class AddProcessedEventsToPayments < ActiveRecord::Migration[7.1]
  def change
    # Webhook events from Stripe can be retried — every event has an
    # `evt_...` id and the handler must be safe to replay. We store the
    # set of event ids already processed for this payment so re-dispatch
    # is a no-op. JSONB array for simplicity (small cardinality per
    # payment; typically 1-3 events: created, succeeded/failed,
    # possibly refunded).
    add_column :payments, :processed_event_ids, :jsonb,
      null: false, default: []
  end
end
