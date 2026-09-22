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

ActiveRecord::Schema[8.1].define(version: 2026_09_21_220820) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "exposures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kanji_id", null: false
    t.string "kind", null: false
    t.datetime "occurred_at"
    t.bigint "sentence_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["kanji_id"], name: "index_exposures_on_kanji_id"
    t.index ["sentence_id"], name: "index_exposures_on_sentence_id"
    t.index ["user_id", "kanji_id", "occurred_at"], name: "index_exposures_on_user_id_and_kanji_id_and_occurred_at"
    t.index ["user_id"], name: "index_exposures_on_user_id"
  end

  create_table "kanji", force: :cascade do |t|
    t.string "character", null: false
    t.datetime "created_at", null: false
    t.integer "frequency_rank"
    t.integer "grade"
    t.string "meaning_summary"
    t.bigint "radical_id"
    t.integer "stroke_count"
    t.string "unicode_codepoint"
    t.datetime "updated_at", null: false
    t.index ["character"], name: "index_kanji_on_character", unique: true
    t.index ["radical_id"], name: "index_kanji_on_radical_id"
  end

  create_table "radicals", force: :cascade do |t|
    t.string "character", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "number"
    t.integer "stroke_count"
    t.datetime "updated_at", null: false
    t.index ["character"], name: "index_radicals_on_character", unique: true
    t.index ["number"], name: "index_radicals_on_number"
  end

  create_table "readings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kanji_id", null: false
    t.string "kind", null: false
    t.string "reading", null: false
    t.datetime "updated_at", null: false
    t.index ["kanji_id", "reading"], name: "index_readings_on_kanji_id_and_reading", unique: true
    t.index ["kanji_id"], name: "index_readings_on_kanji_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.datetime "answered_at", null: false
    t.string "confidence"
    t.boolean "correct", null: false
    t.datetime "created_at", null: false
    t.jsonb "distractors", default: []
    t.string "grade", null: false
    t.float "new_interval"
    t.float "new_mastery"
    t.datetime "presented_at", null: false
    t.float "previous_interval"
    t.float "previous_mastery"
    t.string "question_token"
    t.string "question_type", null: false
    t.integer "response_time_ms"
    t.bigint "reviewable_id", null: false
    t.string "reviewable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_reviews_on_created_at"
    t.index ["question_token"], name: "index_reviews_on_question_token", unique: true
    t.index ["reviewable_type", "reviewable_id"], name: "index_reviews_on_reviewable"
    t.index ["user_id", "reviewable_type", "reviewable_id"], name: "index_reviews_on_user_id_and_reviewable_type_and_reviewable_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "sentence_words", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "end_position"
    t.bigint "sentence_id", null: false
    t.integer "start_position"
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["sentence_id", "word_id"], name: "index_sentence_words_on_sentence_id_and_word_id", unique: true
    t.index ["sentence_id"], name: "index_sentence_words_on_sentence_id"
    t.index ["word_id"], name: "index_sentence_words_on_word_id"
  end

  create_table "sentences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "difficulty"
    t.string "external_id"
    t.jsonb "furigana"
    t.string "generation_version"
    t.text "japanese", null: false
    t.jsonb "kanji_meanings"
    t.string "source", null: false
    t.text "translation"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_sentences_on_external_id"
  end

  create_table "user_kanji", force: :cascade do |t|
    t.float "context_strength", default: 0.0
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.datetime "first_seen_at"
    t.bigint "kanji_id", null: false
    t.datetime "last_seen_at"
    t.float "mastery_score", default: 0.0
    t.float "reading_strength", default: 0.0
    t.float "recognition_strength", default: 0.0
    t.jsonb "srs_state", default: {}
    t.integer "times_correct", default: 0
    t.integer "times_incorrect", default: 0
    t.integer "times_seen", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["due_at"], name: "index_user_kanji_on_due_at"
    t.index ["kanji_id"], name: "index_user_kanji_on_kanji_id"
    t.index ["user_id", "kanji_id"], name: "index_user_kanji_on_user_id_and_kanji_id", unique: true
    t.index ["user_id"], name: "index_user_kanji_on_user_id"
  end

  create_table "user_words", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.float "mastery_score", default: 0.0
    t.jsonb "srs_state", default: {}
    t.integer "times_correct", default: 0
    t.integer "times_incorrect", default: 0
    t.integer "times_seen", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "word_id", null: false
    t.index ["due_at"], name: "index_user_words_on_due_at"
    t.index ["user_id", "word_id"], name: "index_user_words_on_user_id_and_word_id", unique: true
    t.index ["user_id"], name: "index_user_words_on_user_id"
    t.index ["word_id"], name: "index_user_words_on_word_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
  end

  create_table "word_kanji", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "kanji_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["kanji_id"], name: "index_word_kanji_on_kanji_id"
    t.index ["word_id", "kanji_id"], name: "index_word_kanji_on_word_id_and_kanji_id", unique: true
    t.index ["word_id"], name: "index_word_kanji_on_word_id"
  end

  create_table "words", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "frequency_rank"
    t.string "jlpt_level"
    t.text "meaning", null: false
    t.string "part_of_speech"
    t.string "reading", null: false
    t.string "surface", null: false
    t.datetime "updated_at", null: false
    t.index ["frequency_rank"], name: "index_words_on_frequency_rank"
    t.index ["reading"], name: "index_words_on_reading"
    t.index ["surface"], name: "index_words_on_surface", unique: true
  end

  add_foreign_key "exposures", "kanji"
  add_foreign_key "exposures", "sentences"
  add_foreign_key "exposures", "users"
  add_foreign_key "kanji", "radicals"
  add_foreign_key "readings", "kanji"
  add_foreign_key "reviews", "users"
  add_foreign_key "sentence_words", "sentences"
  add_foreign_key "sentence_words", "words"
  add_foreign_key "user_kanji", "kanji"
  add_foreign_key "user_kanji", "users"
  add_foreign_key "user_words", "users"
  add_foreign_key "user_words", "words"
  add_foreign_key "word_kanji", "kanji"
  add_foreign_key "word_kanji", "words"
end
