class AddCurrentTherapistAndIntakeUniqueness < ActiveRecord::Migration[7.1]
  def change
    # The booking redesign (v2): a client is "bound" to one therapist
    # for normal sessions at a time, set by their most recent
    # assessment session and reset on therapist-switch. Nullable for
    # clients who haven't done an assessment yet (and during phased
    # rollout — booking flow that populates this lands in a later
    # phase). FK uses on_delete: nullify so deleting a therapist
    # doesn't cascade-destroy clients.
    add_reference :client_profiles, :current_therapist,
      foreign_key: { to_table: :therapist_profiles, on_delete: :nullify },
      null: true,
      index: true

    # Intake form uniqueness changes from one-per-client to
    # one-per-client-per-therapist. After a switch, the new therapist
    # gets their own intake record for their relationship.
    #
    # The Phase 1 migration created a unique index on (client_profile_id)
    # via the index: { unique: true } on t.references. We drop that and
    # replace with a composite unique on (client_profile_id, author_id).
    remove_index :intake_forms, :client_profile_id
    add_index :intake_forms, :client_profile_id  # non-unique replacement
    add_index :intake_forms, [:client_profile_id, :author_id],
      unique: true,
      name: "idx_unique_intake_per_client_therapist"
  end
end
