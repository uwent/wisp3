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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_190300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "canopy_observations", force: :cascade do |t|
    t.bigint "planting_id", null: false
    t.date "date", null: false
    t.float "pct_cover"
    t.float "lai"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["planting_id", "date"], name: "index_canopy_observations_on_planting_id_and_date", unique: true
    t.check_constraint "lai IS NULL OR lai >= 0::double precision", name: "canopy_observations_lai_positive"
    t.check_constraint "num_nonnulls(pct_cover, lai) = 1", name: "canopy_observations_one_value"
    t.check_constraint "pct_cover IS NULL OR pct_cover >= 0::double precision AND pct_cover <= 100::double precision", name: "canopy_observations_pct_cover_range"
  end

  create_table "farms", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_farms_on_group_id"
  end

  create_table "field_entries", force: :cascade do |t|
    t.bigint "field_id", null: false
    t.date "date", null: false
    t.float "rain_in"
    t.float "irrigation_in"
    t.float "soil_moisture_pct"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_id", "date"], name: "index_field_entries_on_field_id_and_date", unique: true
    t.check_constraint "irrigation_in IS NULL OR irrigation_in >= 0::double precision", name: "field_entries_irrigation_nonnegative"
    t.check_constraint "rain_in IS NULL OR rain_in >= 0::double precision", name: "field_entries_rain_nonnegative"
    t.check_constraint "soil_moisture_pct IS NULL OR soil_moisture_pct >= 0::double precision AND soil_moisture_pct <= 100::double precision", name: "field_entries_moisture_range"
  end

  create_table "field_group_entries", force: :cascade do |t|
    t.bigint "field_group_id", null: false
    t.date "date", null: false
    t.float "rain_in"
    t.float "irrigation_in"
    t.float "soil_moisture_pct"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_group_id", "date"], name: "index_field_group_entries_on_field_group_id_and_date", unique: true
    t.check_constraint "irrigation_in IS NULL OR irrigation_in >= 0::double precision", name: "field_group_entries_irrigation_nonnegative"
    t.check_constraint "rain_in IS NULL OR rain_in >= 0::double precision", name: "field_group_entries_rain_nonnegative"
    t.check_constraint "soil_moisture_pct IS NULL OR soil_moisture_pct >= 0::double precision AND soil_moisture_pct <= 100::double precision", name: "field_group_entries_moisture_range"
  end

  create_table "field_group_members", force: :cascade do |t|
    t.bigint "field_group_id", null: false
    t.bigint "field_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_group_id", "field_id"], name: "index_field_group_members_on_field_group_id_and_field_id", unique: true
    t.index ["field_id"], name: "index_field_group_members_on_field_id"
  end

  create_table "field_groups", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_field_groups_on_group_id"
  end

  create_table "fields", force: :cascade do |t|
    t.bigint "pivot_id", null: false
    t.bigint "soil_type_id", null: false
    t.string "name", null: false
    t.float "area_acres"
    t.float "field_capacity"
    t.float "perm_wilting_pt"
    t.jsonb "boundary"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pivot_id"], name: "index_fields_on_pivot_id"
    t.index ["soil_type_id"], name: "index_fields_on_soil_type_id"
    t.check_constraint "area_acres IS NULL OR area_acres > 0::double precision", name: "fields_area_positive"
  end

  create_table "groups", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "use_model_precip", default: true, null: false
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "group_id", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_memberships_on_group_id"
    t.index ["user_id", "group_id"], name: "index_memberships_on_user_id_and_group_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "pivot_irrigations", force: :cascade do |t|
    t.bigint "pivot_id", null: false
    t.date "date", null: false
    t.float "inches"
    t.float "run_hours"
    t.bigint "field_ids", array: true
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pivot_id", "date"], name: "index_pivot_irrigations_on_pivot_id_and_date", unique: true
    t.check_constraint "inches IS NULL OR inches >= 0::double precision", name: "pivot_irrigations_inches_nonnegative"
    t.check_constraint "num_nonnulls(inches, run_hours) >= 1", name: "pivot_irrigations_amount"
    t.check_constraint "run_hours IS NULL OR run_hours >= 0::double precision", name: "pivot_irrigations_run_hours_nonnegative"
  end

  create_table "pivots", force: :cascade do |t|
    t.bigint "farm_id", null: false
    t.string "name", null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.float "radius_ft"
    t.float "arc_start_deg"
    t.float "arc_end_deg"
    t.string "equipment"
    t.float "pump_capacity_gpm"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["farm_id"], name: "index_pivots_on_farm_id"
    t.check_constraint "(arc_start_deg IS NULL) = (arc_end_deg IS NULL)", name: "pivots_arc_both_or_neither"
    t.check_constraint "pump_capacity_gpm IS NULL OR pump_capacity_gpm > 0::double precision", name: "pivots_pump_capacity_positive"
    t.check_constraint "radius_ft IS NULL OR radius_ft > 0::double precision", name: "pivots_radius_positive"
  end

  create_table "plantings", force: :cascade do |t|
    t.bigint "field_id", null: false
    t.bigint "plant_id", null: false
    t.string "variety"
    t.date "season_start", null: false
    t.date "emergence_date", null: false
    t.date "end_date", null: false
    t.float "max_root_zone_depth", null: false
    t.float "mad_frac", null: false
    t.string "et_method", default: "pct_cover", null: false
    t.float "target_ad_pct"
    t.float "initial_moisture_pct"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_id"], name: "index_plantings_on_field_id"
    t.index ["plant_id"], name: "index_plantings_on_plant_id"
    t.check_constraint "et_method::text = ANY (ARRAY['pct_cover'::character varying, 'lai'::character varying]::text[])", name: "plantings_et_method"
    t.check_constraint "initial_moisture_pct IS NULL OR initial_moisture_pct >= 0::double precision AND initial_moisture_pct <= 100::double precision", name: "plantings_initial_moisture_range"
    t.check_constraint "mad_frac >= 0.05::double precision AND mad_frac <= 0.95::double precision", name: "plantings_mad_frac_range"
    t.check_constraint "max_root_zone_depth > 0::double precision", name: "plantings_mrzd_positive"
    t.check_constraint "season_start <= end_date AND emergence_date <= end_date", name: "plantings_date_order"
    t.check_constraint "target_ad_pct IS NULL OR target_ad_pct >= 0::double precision AND target_ad_pct <= 100::double precision", name: "plantings_target_range"
    t.exclusion_constraint "field_id WITH =, daterange(season_start, end_date, '[]'::text) WITH &&", using: :gist, name: "plantings_no_overlap"
  end

  create_table "plants", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.float "default_max_root_zone_depth", null: false
    t.string "canopy_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_plants_on_key", unique: true
  end

  create_table "soil_types", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.float "field_capacity", null: false
    t.float "perm_wilting_pt", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_soil_types_on_key", unique: true
    t.check_constraint "perm_wilting_pt > 0::double precision AND perm_wilting_pt < field_capacity AND field_capacity < 0.6::double precision", name: "soil_types_water_fractions"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "first_name"
    t.string "last_name"
    t.boolean "admin", default: false, null: false
    t.string "unit_system", default: "imperial", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sign_in_code_digest"
    t.datetime "sign_in_code_sent_at"
    t.integer "sign_in_code_attempts", default: 0, null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "canopy_observations", "plantings"
  add_foreign_key "farms", "groups"
  add_foreign_key "field_entries", "fields"
  add_foreign_key "field_group_entries", "field_groups"
  add_foreign_key "field_group_members", "field_groups"
  add_foreign_key "field_group_members", "fields"
  add_foreign_key "field_groups", "groups"
  add_foreign_key "fields", "pivots"
  add_foreign_key "fields", "soil_types"
  add_foreign_key "memberships", "groups", on_delete: :cascade
  add_foreign_key "memberships", "users", on_delete: :cascade
  add_foreign_key "pivot_irrigations", "pivots"
  add_foreign_key "pivots", "farms"
  add_foreign_key "plantings", "fields"
  add_foreign_key "plantings", "plants"
end
