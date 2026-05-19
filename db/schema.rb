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

ActiveRecord::Schema[7.1].define(version: 2026_02_01_000009) do
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

  create_table "appointments", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "therapist_profile_id", null: false
    t.bigint "availability_slot_id", null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reminder_sent_at"
    t.index ["availability_slot_id"], name: "idx_one_active_appointment_per_slot", unique: true, where: "(status <> ALL (ARRAY[2, 4]))"
    t.index ["availability_slot_id"], name: "index_appointments_on_availability_slot_id"
    t.index ["client_profile_id", "status"], name: "index_appointments_on_client_profile_id_and_status"
    t.index ["client_profile_id"], name: "index_appointments_on_client_profile_id"
    t.index ["reminder_sent_at"], name: "index_appointments_on_reminder_sent_at"
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

  create_table "client_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "date_of_birth"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_client_profiles_on_user_id", unique: true
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
    t.bigint "appointment_id", null: false
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
    t.index ["appointment_id"], name: "index_payments_on_appointment_id", unique: true
    t.index ["client_profile_id"], name: "index_payments_on_client_profile_id"
    t.index ["provider_reference"], name: "index_payments_on_provider_reference"
    t.index ["status"], name: "index_payments_on_status"
    t.check_constraint "amount_cents >= 0", name: "chk_payment_amount_non_negative"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointments", "availability_slots", on_delete: :cascade
  add_foreign_key "appointments", "client_profiles", on_delete: :cascade
  add_foreign_key "appointments", "therapist_profiles", on_delete: :cascade
  add_foreign_key "availability_slots", "therapist_profiles", on_delete: :cascade
  add_foreign_key "client_profiles", "users", on_delete: :cascade
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "payments", "appointments", on_delete: :cascade
  add_foreign_key "payments", "client_profiles", on_delete: :cascade
  add_foreign_key "therapist_profiles", "users", on_delete: :cascade
  add_foreign_key "therapist_specializations", "specializations", on_delete: :cascade
  add_foreign_key "therapist_specializations", "therapist_profiles", on_delete: :cascade
end
