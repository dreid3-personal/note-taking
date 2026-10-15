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

ActiveRecord::Schema[8.1].define(version: 2026_10_15_000006) do
  create_table "folders", force: :cascade do |t|
    t.string "name", null: false
    t.integer "author_id", null: false
    t.integer "parent_id"
    t.integer "team_id"
    t.string "everyone_access", default: "none", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_folders_on_author_id"
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["team_id"], name: "index_folders_on_team_id", unique: true
    t.check_constraint "everyone_access IN ('none', 'view', 'edit')", name: "folders_everyone_access_check"
    t.check_constraint "team_id IS NULL OR parent_id IS NULL", name: "folders_team_folder_top_level_check"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "team_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_memberships_on_user_id_and_team_id", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.string "title", null: false
    t.text "body", default: "", null: false
    t.integer "author_id", null: false
    t.integer "folder_id"
    t.string "everyone_access", default: "none", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_notes_on_author_id"
    t.index ["folder_id"], name: "index_notes_on_folder_id"
    t.check_constraint "everyone_access IN ('none', 'view', 'edit')", name: "notes_everyone_access_check"
  end

  create_table "shares", force: :cascade do |t|
    t.integer "folder_id"
    t.integer "note_id"
    t.integer "user_id"
    t.integer "team_id"
    t.string "access", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id", "team_id"], name: "index_shares_on_folder_id_and_team_id", unique: true
    t.index ["folder_id", "user_id"], name: "index_shares_on_folder_id_and_user_id", unique: true
    t.index ["note_id", "team_id"], name: "index_shares_on_note_id_and_team_id", unique: true
    t.index ["note_id", "user_id"], name: "index_shares_on_note_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_shares_on_team_id"
    t.index ["user_id"], name: "index_shares_on_user_id"
    t.check_constraint "(folder_id IS NULL) <> (note_id IS NULL)", name: "shares_one_item_check"
    t.check_constraint "(user_id IS NULL) <> (team_id IS NULL)", name: "shares_one_grantee_check"
    t.check_constraint "access IN ('view', 'edit')", name: "shares_access_check"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower(name)", name: "index_teams_on_lower_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower(email)", name: "index_users_on_lower_email", unique: true
  end

  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "teams"
  add_foreign_key "folders", "users", column: "author_id"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "notes", "folders"
  add_foreign_key "notes", "users", column: "author_id"
  add_foreign_key "shares", "folders"
  add_foreign_key "shares", "notes"
  add_foreign_key "shares", "teams"
  add_foreign_key "shares", "users"
end
