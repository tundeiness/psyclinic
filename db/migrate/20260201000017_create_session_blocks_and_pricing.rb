class CreateSessionBlocksAndPricing < ActiveRecord::Migration[7.1]
  def change
    # ---- pricing keys on app_settings ----
    # All amounts in kobo (smallest naira unit; 1 NGN = 100 kobo).
    # Defaults match the v2 design doc (₦50,000 assessment,
    # ₦300,000 6-session block, 60/40 installment split).
    add_column :app_settings, :assessment_session_price_cents, :integer,
      null: false, default: 5_000_000
    add_column :app_settings, :block_full_price_cents, :integer,
      null: false, default: 30_000_000
    add_column :app_settings, :block_installment_first_pct, :integer,
      null: false, default: 60
    add_column :app_settings, :block_installment_second_pct, :integer,
      null: false, default: 40

    # ---- session_blocks table ----
    # Created BEFORE we add appointments.session_block_id, since that
    # FK references session_blocks.id.
    create_table :session_blocks do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :therapist_profile, null: false,
        foreign_key: { on_delete: :restrict }

      t.datetime :purchased_at, null: false

      # Always 6 in the current design but kept as a column for
      # future flexibility (different block sizes per practice).
      t.integer :sessions_total, null: false, default: 6
      t.integer :sessions_used,  null: false, default: 0

      # payment_mode: 0=full, 1=installment
      t.integer :payment_mode, null: false, default: 0

      # Foreign keys back to payments. Polymorphic Payment refactor
      # comes in Phase 5 — for now we keep these as nullable FKs.
      t.references :first_payment,
        foreign_key: { to_table: :payments, on_delete: :nullify },
        null: true
      t.references :second_payment,
        foreign_key: { to_table: :payments, on_delete: :nullify },
        null: true

      # status: 0=active, 1=completed, 2=refunded, 3=forfeited
      # (forfeited = client switched therapists with unused sessions
      # remaining per Q15 final decision)
      t.integer :status, null: false, default: 0

      t.text :notes

      t.timestamps
    end

    add_index :session_blocks, [:client_profile_id, :status]
    add_index :session_blocks, [:therapist_profile_id, :status]

    # ---- appointment kind + block association ----
    # session_kind distinguishes the one-off paid assessment session
    # (intake form goes against this) from normal sessions that draw
    # against a SessionBlock. Existing rows backfill to :normal since
    # that's the legacy semantics. Integer enum to keep state mapping
    # cheap and re-orderable.
    add_column :appointments, :session_kind, :integer,
      null: false, default: 0  # 0 = normal
    add_index :appointments, :session_kind

    # Nullable: assessment sessions have no block (they're individually
    # paid); normal sessions point to the block that funded them.
    # nullify on block delete so a deleted block doesn't cascade-destroy
    # historical appointments; appointments themselves keep audit trail.
    add_reference :appointments, :session_block,
      foreign_key: { on_delete: :nullify }, null: true
  end
end
