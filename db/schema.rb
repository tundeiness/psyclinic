# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_02_01_000019) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.integer "flat_rate_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assessment_session_price_cents", default: 5000000, null: false
    t.integer "block_full_price_cents", default: 30000000, null: false
    t.integer "block_installment_first_pct", default: 60, null: false
    t.integer "block_installment_second_pct", default: 40, null: false
  end

  create_table "appointments", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "therapist_profile_id", null: false
    t.bigint "availability_slot_id", null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reminder_sent_at"
    t.integer "session_kind", default: 0, null: false
    t.bigint "session_block_id"
    t.index ["availability_slot_id"], name: "idx_one_active_appointment_per_slot", unique: true, where: "(status <> ALL (ARRAY[2, 4]))"
    t.index ["availability_slot_id"], name: "index_appointments_on_availability_slot_id"
    t.index ["client_profile_id", "status"], name: "index_appointments_on_client_profile_id_and_status"
    t.index ["client_profile_id"], name: "index_appointments_on_client_profile_id"
    t.index ["reminder_sent_at"], name: "index_appointments_on_reminder_sent_at"
    t.index ["session_block_id"], name: "index_appointments_on_session_block_id"
    t.index ["session_kind"], name: "index_appointments_on_session_kind"
    t.index ["therapist_profile_id", "status"], name: "index_appointments_on_therapist_profile_id_and_status"
    t.index ["therapist_profile_id"], name: "index_appointments_on_therapist_profile_id"
  end

  create_table "availability_slots", force: :cascade do |t|
    t.bigint "therapist_profile_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_availability_slots_on_status"
    t.index ["therapist_profile_id", "starts_at", "ends_at"], name: "idx_unique_slot_per_therapist", unique: true
    t.index ["therapist_profile_id", "starts_at"], name: "index_availability_slots_on_therapist_profile_id_and_starts_at"
    t.index ["therapist_profile_id"], name: "index_availability_slots_on_therapist_profile_id"
    t.check_constraint "ends_at > starts_at", name: "chk_slot_time_order"
  end

  create_table "blog_images", force: :cascade do |t|
    t.bigint "blog_post_id", null: false
    t.string "alt", default: ""
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blog_post_id", "position"], name: "index_blog_images_on_blog_post_id_and_position"
    t.index ["blog_post_id"], name: "index_blog_images_on_blog_post_id"
  end

  create_table "blog_posts", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.integer "status", default: 0, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_blog_posts_on_author_id"
    t.index ["status", "published_at"], name: "index_blog_posts_on_status_and_published_at"
  end

  create_table "client_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "date_of_birth"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "current_therapist_id"
    t.index ["current_therapist_id"], name: "index_client_profiles_on_current_therapist_id"
    t.index ["user_id"], name: "index_client_profiles_on_user_id", unique: true
  end

  create_table "dass_assessments", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "appointment_id"
    t.bigint "author_id", null: false
    t.date "assessment_date", null: false
    t.integer "item_1"
    t.integer "item_2"
    t.integer "item_3"
    t.integer "item_4"
    t.integer "item_5"
    t.integer "item_6"
    t.integer "item_7"
    t.integer "item_8"
    t.integer "item_9"
    t.integer "item_10"
    t.integer "item_11"
    t.integer "item_12"
    t.integer "item_13"
    t.integer "item_14"
    t.integer "item_15"
    t.integer "item_16"
    t.integer "item_17"
    t.integer "item_18"
    t.integer "item_19"
    t.integer "item_20"
    t.integer "item_21"
    t.integer "item_22"
    t.integer "item_23"
    t.integer "item_24"
    t.integer "item_25"
    t.integer "item_26"
    t.integer "item_27"
    t.integer "item_28"
    t.integer "item_29"
    t.integer "item_30"
    t.integer "item_31"
    t.integer "item_32"
    t.integer "item_33"
    t.integer "item_34"
    t.integer "item_35"
    t.integer "item_36"
    t.integer "item_37"
    t.integer "item_38"
    t.integer "item_39"
    t.integer "item_40"
    t.integer "item_41"
    t.integer "item_42"
    t.integer "depression_score"
    t.integer "anxiety_score"
    t.integer "stress_score"
    t.string "depression_severity"
    t.string "anxiety_severity"
    t.string "stress_severity"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_dass_assessments_on_appointment_id"
    t.index ["author_id"], name: "index_dass_assessments_on_author_id"
    t.index ["client_profile_id"], name: "index_dass_assessments_on_client_profile_id"
    t.index ["signed_by_id"], name: "index_dass_assessments_on_signed_by_id"
  end

  create_table "intake_forms", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "author_id", null: false
    t.date "session_date"
    t.time "session_start_time"
    t.time "session_end_time"
    t.string "preferred_address"
    t.date "date_of_birth"
    t.integer "age_at_intake"
    t.string "phone_number"
    t.string "state_of_origin"
    t.string "sex"
    t.string "relationship_status"
    t.string "gender_identity"
    t.string "email_address"
    t.text "home_address"
    t.string "profession"
    t.text "work_hours"
    t.text "religion_spirituality"
    t.text "referral_source"
    t.text "presenting_complaint"
    t.text "therapy_goals"
    t.boolean "self_harm_history"
    t.text "self_harm_details"
    t.string "suicidal_ideations"
    t.boolean "suicide_plan_present"
    t.boolean "suicide_means_available"
    t.boolean "prior_therapy"
    t.text "prior_therapy_details"
    t.jsonb "medications", default: [], null: false
    t.jsonb "history", default: [], null: false
    t.jsonb "family_tree", default: [], null: false
    t.jsonb "substance_use", default: [], null: false
    t.text "living_conditions"
    t.text "other_concerns"
    t.boolean "legal_proceedings"
    t.text "legal_proceedings_details"
    t.string "legal_proceedings_status"
    t.string "emergency_contact_name"
    t.string "emergency_contact_relationship"
    t.string "emergency_contact_phone"
    t.text "emergency_contact_address"
    t.text "other_details"
    t.text "case_formulation"
    t.text "provisional_diagnoses"
    t.text "treatment_plan"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_intake_forms_on_author_id"
    t.index ["client_profile_id", "author_id"], name: "idx_unique_intake_per_client_therapist", unique: true
    t.index ["client_profile_id"], name: "index_intake_forms_on_client_profile_id"
    t.index ["signed_by_id"], name: "index_intake_forms_on_signed_by_id"
  end

  create_table "jwt_denylist", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["jti"], name: "index_jwt_denylist_on_jti", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.string "subject_type"
    t.bigint "subject_id"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject_type_and_subject_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "appointment_id"
    t.bigint "client_profile_id", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.integer "status", default: 0, null: false
    t.string "provider"
    t.string "provider_reference"
    t.jsonb "provider_payload", default: {}, null: false
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "processed_event_ids", default: [], null: false
    t.string "payable_type", null: false
    t.bigint "payable_id", null: false
    t.index ["appointment_id"], name: "index_payments_on_appointment_id"
    t.index ["client_profile_id"], name: "index_payments_on_client_profile_id"
    t.index ["payable_type", "payable_id"], name: "idx_unique_payment_per_payable", unique: true
    t.index ["provider_reference"], name: "index_payments_on_provider_reference"
    t.index ["status"], name: "index_payments_on_status"
    t.check_constraint "amount_cents >= 0", name: "chk_payment_amount_non_negative"
  end

  create_table "service_plan_notes", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "appointment_id"
    t.bigint "author_id", null: false
    t.date "session_date"
    t.time "session_start_time"
    t.time "session_end_time"
    t.text "review"
    t.text "addressed_and_plan"
    t.text "clinician_impression"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_service_plan_notes_on_appointment_id"
    t.index ["author_id"], name: "index_service_plan_notes_on_author_id"
    t.index ["client_profile_id"], name: "index_service_plan_notes_on_client_profile_id", unique: true
    t.index ["signed_by_id"], name: "index_service_plan_notes_on_signed_by_id"
  end

  create_table "session_blocks", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "therapist_profile_id", null: false
    t.datetime "purchased_at", null: false
    t.integer "sessions_total", default: 6, null: false
    t.integer "sessions_used", default: 0, null: false
    t.integer "payment_mode", default: 0, null: false
    t.bigint "first_payment_id"
    t.bigint "second_payment_id"
    t.integer "status", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_profile_id", "status"], name: "index_session_blocks_on_client_profile_id_and_status"
    t.index ["client_profile_id"], name: "index_session_blocks_on_client_profile_id"
    t.index ["first_payment_id"], name: "index_session_blocks_on_first_payment_id"
    t.index ["second_payment_id"], name: "index_session_blocks_on_second_payment_id"
    t.index ["therapist_profile_id", "status"], name: "index_session_blocks_on_therapist_profile_id_and_status"
    t.index ["therapist_profile_id"], name: "index_session_blocks_on_therapist_profile_id"
  end

  create_table "session_notes", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "client_profile_id", null: false
    t.bigint "author_id", null: false
    t.integer "session_number"
    t.date "session_date"
    t.time "session_start_time"
    t.time "session_end_time"
    t.text "review"
    t.text "addressed_and_plan"
    t.text "clinician_impression"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_session_notes_on_appointment_id", unique: true
    t.index ["author_id"], name: "index_session_notes_on_author_id"
    t.index ["client_profile_id"], name: "index_session_notes_on_client_profile_id"
    t.index ["signed_by_id"], name: "index_session_notes_on_signed_by_id"
  end

  create_table "specializations", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_specializations_on_name", unique: true
  end

  create_table "therapist_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "bio"
    t.string "license_number"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "headline"
    t.integer "years_experience"
    t.integer "hourly_rate_cents", default: 0, null: false
    t.boolean "co_admin", default: false, null: false
    t.index ["co_admin"], name: "index_therapist_profiles_on_co_admin"
    t.index ["user_id"], name: "index_therapist_profiles_on_user_id", unique: true
  end

  create_table "therapist_specializations", force: :cascade do |t|
    t.bigint "therapist_profile_id", null: false
    t.bigint "specialization_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["specialization_id"], name: "index_therapist_specializations_on_specialization_id"
    t.index ["therapist_profile_id", "specialization_id"], name: "idx_unique_therapist_specialization", unique: true
    t.index ["therapist_profile_id"], name: "index_therapist_specializations_on_therapist_profile_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "phone"
    t.integer "role", default: 0, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "wheel_of_life_assessments", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "appointment_id"
    t.bigint "author_id", null: false
    t.date "assessment_date", null: false
    t.jsonb "scores", default: {}, null: false
    t.jsonb "totals", default: {}, null: false
    t.text "focus_area"
    t.text "current_state"
    t.text "whats_missing"
    t.text "what_to_create"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_wheel_of_life_assessments_on_appointment_id"
    t.index ["author_id"], name: "index_wheel_of_life_assessments_on_author_id"
    t.index ["client_profile_id"], name: "index_wheel_of_life_assessments_on_client_profile_id"
    t.index ["signed_by_id"], name: "index_wheel_of_life_assessments_on_signed_by_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointments", "availability_slots", on_delete: :cascade
  add_foreign_key "appointments", "client_profiles", on_delete: :cascade
  add_foreign_key "appointments", "session_blocks", on_delete: :nullify
  add_foreign_key "appointments", "therapist_profiles", on_delete: :cascade
  add_foreign_key "availability_slots", "therapist_profiles", on_delete: :cascade
  add_foreign_key "blog_images", "blog_posts", on_delete: :cascade
  add_foreign_key "blog_posts", "users", column: "author_id", on_delete: :cascade
  add_foreign_key "client_profiles", "therapist_profiles", column: "current_therapist_id", on_delete: :nullify
  add_foreign_key "client_profiles", "users", on_delete: :cascade
  add_foreign_key "dass_assessments", "appointments", on_delete: :nullify
  add_foreign_key "dass_assessments", "client_profiles", on_delete: :cascade
  add_foreign_key "dass_assessments", "users", column: "author_id", on_delete: :restrict
  add_foreign_key "dass_assessments", "users", column: "signed_by_id"
  add_foreign_key "intake_forms", "client_profiles", on_delete: :cascade
  add_foreign_key "intake_forms", "users", column: "author_id", on_delete: :restrict
  add_foreign_key "intake_forms", "users", column: "signed_by_id"
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "payments", "appointments", on_delete: :cascade
  add_foreign_key "payments", "client_profiles", on_delete: :cascade
  add_foreign_key "service_plan_notes", "appointments", on_delete: :nullify
  add_foreign_key "service_plan_notes", "client_profiles", on_delete: :cascade
  add_foreign_key "service_plan_notes", "users", column: "author_id", on_delete: :restrict
  add_foreign_key "service_plan_notes", "users", column: "signed_by_id"
  add_foreign_key "session_blocks", "client_profiles", on_delete: :cascade
  add_foreign_key "session_blocks", "payments", column: "first_payment_id", on_delete: :nullify
  add_foreign_key "session_blocks", "payments", column: "second_payment_id", on_delete: :nullify
  add_foreign_key "session_blocks", "therapist_profiles", on_delete: :restrict
  add_foreign_key "session_notes", "appointments", on_delete: :cascade
  add_foreign_key "session_notes", "client_profiles", on_delete: :cascade
  add_foreign_key "session_notes", "users", column: "author_id", on_delete: :restrict
  add_foreign_key "session_notes", "users", column: "signed_by_id"
  add_foreign_key "therapist_profiles", "users", on_delete: :cascade
  add_foreign_key "therapist_specializations", "specializations", on_delete: :cascade
  add_foreign_key "therapist_specializations", "therapist_profiles", on_delete: :cascade
  add_foreign_key "wheel_of_life_assessments", "appointments", on_delete: :nullify
  add_foreign_key "wheel_of_life_assessments", "client_profiles", on_delete: :cascade
  add_foreign_key "wheel_of_life_assessments", "users", column: "author_id", on_delete: :restrict
  add_foreign_key "wheel_of_life_assessments", "users", column: "signed_by_id"
end
