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

ActiveRecord::Schema[8.1].define(version: 2026_08_31_000001) do
  create_table "favourites", force: :cascade do |t|
    t.integer "hotel_id", null: false
    t.string "tenant_id", default: "north", null: false
    t.string "user_id", null: false
    t.index ["tenant_id", "user_id", "hotel_id"], name: "index_favourites_on_tenant_id_and_user_id_and_hotel_id", unique: true
  end
end
