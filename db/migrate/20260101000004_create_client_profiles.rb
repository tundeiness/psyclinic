class CreateClientProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :client_profiles do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }

      # The pairing: set by Admin. Nullable until paired.
      t.references :therapist_profile,
        null: true,
        foreign_key: { on_delete: :nullify }

      t.date :date_of_birth
      t.text :notes

      t.timestamps
    end
  end
end
