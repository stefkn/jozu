class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reviewable, polymorphic: true, null: false

      t.string :question_type, null: false
      t.string :grade, null: false
      t.jsonb :distractors, default: []

      t.datetime :presented_at, null: false
      t.datetime :answered_at, null: false
      t.boolean :correct, null: false
      t.integer :response_time_ms
      t.string :confidence

      t.float :previous_interval
      t.float :new_interval
      t.float :previous_mastery
      t.float :new_mastery

      t.string :question_token

      t.timestamps
    end

    add_index :reviews, %i[user_id reviewable_type reviewable_id]
    add_index :reviews, :created_at
    add_index :reviews, :question_token, unique: true
  end
end
