class RemovePairingFromClientProfiles < ActiveRecord::Migration[7.1]
  def up
    # Pairing is removed: clients now book any approved therapist directly.
    remove_reference :client_profiles, :therapist_profile, foreign_key: true
  end

  def down
    add_reference :client_profiles, :therapist_profile,
      null: true, foreign_key: { on_delete: :nullify }
  end
end
