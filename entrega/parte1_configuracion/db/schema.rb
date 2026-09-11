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

ActiveRecord::Schema[7.2].define(version: 2026_09_10_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "line_item_directives", force: :cascade do |t|
    t.bigint "line_item_id", null: false
    t.string "directive_type", limit: 10, null: false
    t.string "unit_uid", limit: 64
    t.string "key", limit: 64, null: false
    t.text "value"
    t.string "source", limit: 16, null: false
    t.integer "version", null: false
    t.datetime "created_at", null: false
    t.index ["line_item_id", "directive_type", "unit_uid", "key", "version", "created_at", "id"], name: "index_line_item_directives_on_resolution", order: { version: :desc, created_at: :desc, id: :desc }
    t.check_constraint "(directive_type::text = 'header'::text) = (unit_uid IS NULL)", name: "chk_line_item_directives_scope"
    t.check_constraint "directive_type::text = ANY (ARRAY['header'::character varying, 'unit'::character varying]::text[])", name: "chk_line_item_directives_type"
  end
end
