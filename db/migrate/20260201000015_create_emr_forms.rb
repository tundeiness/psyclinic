class CreateEmrForms < ActiveRecord::Migration[7.1]
  def change
    # Out with the old. ClientNote was free-form text-per-client; the
    # new EMR design replaces it with structured forms.
    drop_table :client_notes, if_exists: true

    # ============================================================
    # 1) Intake form — one per client, on first session.
    # Mirrors the CAMBC Client Intake Form fields.
    # ============================================================
    create_table :intake_forms do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }

      # Session metadata
      t.date     :session_date
      t.time     :session_start_time
      t.time     :session_end_time

      # Demographics & identity (collected by clinician at intake;
      # some of these duplicate the user's profile data but the intake
      # is its own clinical record, so we capture it explicitly here).
      t.string   :preferred_address
      t.date     :date_of_birth
      t.integer  :age_at_intake
      t.string   :phone_number
      t.string   :state_of_origin
      t.string   :sex
      t.string   :relationship_status
      t.string   :gender_identity
      t.string   :email_address
      t.text     :home_address
      t.string   :profession
      t.text     :work_hours
      t.text     :religion_spirituality
      t.text     :referral_source

      # Presenting complaint / goals
      t.text     :presenting_complaint
      t.text     :therapy_goals

      # Suicide risk screen — high-importance fields. Booleans default
      # to nil so "not yet asked" is distinguishable from "no".
      t.boolean  :self_harm_history
      t.text     :self_harm_details
      t.string   :suicidal_ideations           # past/present/none
      t.boolean  :suicide_plan_present
      t.boolean  :suicide_means_available

      # History
      t.boolean  :prior_therapy
      t.text     :prior_therapy_details

      # Stored as JSON arrays of records — table-shaped form data
      # without separate child tables. Schema documented in the model.
      t.jsonb    :medications,  null: false, default: []
      t.jsonb    :history,      null: false, default: []
      t.jsonb    :family_tree,  null: false, default: []
      t.jsonb    :substance_use, null: false, default: []

      t.text     :living_conditions
      t.text     :other_concerns

      t.boolean  :legal_proceedings
      t.text     :legal_proceedings_details
      t.string   :legal_proceedings_status

      # Emergency contact
      t.string   :emergency_contact_name
      t.string   :emergency_contact_relationship
      t.string   :emergency_contact_phone
      t.text     :emergency_contact_address

      t.text     :other_details

      # Clinical summary (last page of the CAMBC form)
      t.text     :case_formulation
      t.text     :provisional_diagnoses
      t.text     :treatment_plan

      # Signing
      t.datetime :signed_at
      t.references :signed_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # ============================================================
    # 2) Session note — per appointment.
    # ============================================================
    create_table :session_notes do |t|
      t.references :appointment, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }

      t.integer  :session_number
      t.date     :session_date
      t.time     :session_start_time
      t.time     :session_end_time

      # Narrative sections (the Cerca session-notes structure).
      t.text     :review
      t.text     :addressed_and_plan
      t.text     :clinician_impression

      t.datetime :signed_at
      t.references :signed_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # ============================================================
    # 3) Service plan note — per client, written at second session.
    # Same structural shape as session note but a different record
    # because it's a one-off treatment-planning document.
    # ============================================================
    create_table :service_plan_notes do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :appointment,
        foreign_key: { on_delete: :nullify }
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }

      t.date     :session_date
      t.time     :session_start_time
      t.time     :session_end_time

      t.text     :review
      t.text     :addressed_and_plan
      t.text     :clinician_impression

      t.datetime :signed_at
      t.references :signed_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # ============================================================
    # 4) DASS-42 — depression/anxiety/stress assessment.
    # Items 1..42 stored individually as small integers 0-3.
    # Subscale sums and severity labels computed in the model;
    # cached here in *_score columns at save time for query speed.
    # ============================================================
    create_table :dass_assessments do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :appointment,
        foreign_key: { on_delete: :nullify }
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }

      t.date     :assessment_date, null: false

      # 42 Likert items, validated 0-3 in the model.
      (1..42).each do |i|
        t.integer "item_#{i}"
      end

      # Cached subscale scores (sum of relevant items × 2 per DASS-42
      # scoring rules).
      t.integer :depression_score
      t.integer :anxiety_score
      t.integer :stress_score

      # Severity labels: normal / mild / moderate / severe / extremely_severe
      t.string  :depression_severity
      t.string  :anxiety_severity
      t.string  :stress_severity

      t.datetime :signed_at
      t.references :signed_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # ============================================================
    # 5) Wheel of Life — 9 life areas, 4-5 items each, 1-10 Likert.
    # Per-area totals + percentage cached at save time. Reflection
    # questions stored as text.
    # ============================================================
    create_table :wheel_of_life_assessments do |t|
      t.references :client_profile, null: false,
        foreign_key: { on_delete: :cascade }
      t.references :appointment,
        foreign_key: { on_delete: :nullify }
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }

      t.date     :assessment_date, null: false

      # 41 items across 9 areas. Stored as JSON: keys are
      # area names, values are arrays of per-item integers.
      # Documented in the model. Single JSON keeps the column count sane.
      t.jsonb    :scores, null: false, default: {}

      # Cached totals + percentages per area.
      t.jsonb    :totals, null: false, default: {}

      # Reflection questions (free text).
      t.text     :focus_area
      t.text     :current_state
      t.text     :whats_missing
      t.text     :what_to_create

      t.datetime :signed_at
      t.references :signed_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
