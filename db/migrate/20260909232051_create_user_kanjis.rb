class CreateUserKanjis < ActiveRecord::Migration[8.1]
  def change
    create_table :user_kanji do |t|
      t.references :user, null: false, foreign_key: true
      t.references :kanji, null: false, foreign_key: { to_table: :kanji }

      t.float :mastery_score, default: 0.0
      t.float :recognition_strength, default: 0.0
      t.float :reading_strength, default: 0.0
      t.float :context_strength, default: 0.0

      t.jsonb :srs_state, default: {}
      t.datetime :due_at

      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.integer :times_seen, default: 0
      t.integer :times_correct, default: 0
      t.integer :times_incorrect, default: 0

      t.timestamps
    end

    add_index :user_kanji, %i[user_id kanji_id], unique: true
    add_index :user_kanji, :due_at
  end
end
