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

ActiveRecord::Schema[7.1].define(version: 2026_01_01_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "appointments", force: :cascade do |t|
    t.bigint "client_profile_id", null: false
    t.bigint "therapist_profile_id", null: false
    t.bigint "availability_slot_id", null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["availability_slot_id"], name: "idx_one_active_appointment_per_slot", unique: true, where: "(status <> 2)"
    t.index ["availability_slot_id"], name: "index_appointments_on_availability_slot_id"
    t.index ["client_profile_id", "status"], name: "index_appointments_on_client_profile_id_and_status"
    t.index ["client_profile_id"], name: "index_appointments_on_client_profile_id"
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
    t.bigint "therapist_profile_id"
    t.date "date_of_birth"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["therapist_profile_id"], name: "index_client_profiles_on_therapist_profile_id"
    t.index ["user_id"], name: "index_client_profiles_on_user_id", unique: true
  end

  create_table "jwt_denylist", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["jti"], name: "index_jwt_denylist_on_jti", unique: true
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "appointments", "availability_slots", on_delete: :cascade
  add_foreign_key "appointments", "client_profiles", on_delete: :cascade
  add_foreign_key "appointments", "therapist_profiles", on_delete: :cascade
  add_foreign_key "availability_slots", "therapist_profiles", on_delete: :cascade
  add_foreign_key "client_profiles", "therapist_profiles", on_delete: :nullify
  add_foreign_key "client_profiles", "users", on_delete: :cascade
  add_foreign_key "therapist_profiles", "users", on_delete: :cascade
  add_foreign_key "therapist_specializations", "specializations", on_delete: :cascade
  add_foreign_key "therapist_specializations", "therapist_profiles", on_delete: :cascade
end
