class CreateClientTherapistAssignments < ActiveRecord::Migration[7.1]
  # Phase 14: durable audit of which therapist treated which client
  # over time. Each switch closes the prior assignment (sets ended_at)
  # and opens a new one. The current_therapist_id on client_profile
  # remains the fast lookup; this table is the history.
  #
  # forfeited_block_id captures which block (if any) was sacrificed
  # to make the switch. forfeited_sessions_count is the audit number:
  # how many unused sessions the client gave up. Per the contract,
  # those are non-refundable.
  #
  # reason is optional free text the client provides ("I felt the
  # approach wasn't a fit"). Useful for clinic operations and
  # therapist supervision.
  def change
    create_table :client_therapist_assignments do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :from_therapist, null: true,
        foreign_key: { to_table: :therapist_profiles, on_delete: :restrict }
      t.references :to_therapist, null: false,
        foreign_key: { to_table: :therapist_profiles, on_delete: :restrict }

      t.datetime :started_at, null: false
      t.datetime :ended_at, null: true

      t.references :forfeited_block, null: true,
        foreign_key: { to_table: :session_blocks, on_delete: :nullify }
      t.integer  :forfeited_sessions_count, null: false, default: 0

      t.text :reason

      t.timestamps
    end

    # Only one open assignment per client. A partial unique index
    # enforces this — multiple closed rows are fine, but at any time
    # there's exactly one (or zero, for clients pre-assessment) open
    # row.
    add_index :client_therapist_assignments,
      :client_profile_id,
      unique: true,
      where: "ended_at IS NULL",
      name: "idx_one_open_assignment_per_client"
  end
end
