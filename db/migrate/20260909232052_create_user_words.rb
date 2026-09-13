class CreateUserWords < ActiveRecord::Migration[8.1]
  def change
    create_table :user_words do |t|
      t.references :user, null: false, foreign_key: true
      t.references :word, null: false, foreign_key: true

      t.float :mastery_score, default: 0.0
      t.jsonb :srs_state, default: {}
      t.datetime :due_at

      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.integer :times_seen, default: 0
      t.integer :times_correct, default: 0
      t.integer :times_incorrect, default: 0

      t.timestamps
    end

    add_index :user_words, %i[user_id word_id], unique: true
    add_index :user_words, :due_at
  end
end
