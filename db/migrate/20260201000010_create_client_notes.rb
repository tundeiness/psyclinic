class CreateClientNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :client_notes do |t|
      t.references :therapist_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.text :body, null: false

      t.timestamps
    end

    # Fast lookup of a therapist's notes for a given client.
    add_index :client_notes,
      %i[therapist_profile_id client_profile_id created_at],
      name: "idx_client_notes_therapist_client_time"
  end
end
