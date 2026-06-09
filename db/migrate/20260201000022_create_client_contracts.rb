class CreateClientContracts < ActiveRecord::Migration[7.1]
  # Phase 8: Cerca Africa requires every client to sign a services
  # contract before they can purchase a session block. The contract
  # captures consent to the clinic's policies (confidentiality,
  # rescheduling, fees, etc).
  #
  # Two signing methods supported:
  #  - :electronic — the client types their name and confirms the date;
  #    no human certification needed (the typing IS the signature, audit
  #    trail is timestamp + IP).
  #  - :uploaded — the client downloads the PDF, signs by hand, uploads
  #    a scan. A therapist or admin must then certify it for it to count.
  #
  # contract_version is a string ("v1-2026") so the document can evolve;
  # clients holding an old version need to re-sign when buying a new
  # block, but their current block keeps working.
  def change
    add_column :app_settings, :current_contract_version, :string,
      null: false, default: "v1-2026"

    create_table :client_contracts do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }

      t.string  :contract_version,   null: false
      t.integer :signature_method,   null: false  # 0=electronic, 1=uploaded
      t.datetime :signed_at,         null: false

      # Electronic-signing fields.
      t.string :electronic_signature_name
      t.string :signed_from_ip

      # Sponsor capture (text-only; no sponsor account in v1). Required
      # when the client is a minor; optional otherwise.
      t.string :sponsor_name
      t.string :sponsor_signature_typed

      # Certification (uploaded contracts only).
      t.references :certified_by_user, foreign_key: { to_table: :users,
        on_delete: :nullify }
      t.datetime :certified_at

      t.timestamps
    end

    # Index for the common "does this client have a valid contract for
    # the current version" query.
    add_index :client_contracts,
      [:client_profile_id, :contract_version],
      name: "idx_client_contracts_lookup"
  end
end
