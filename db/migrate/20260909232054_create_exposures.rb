class CreateExposures < ActiveRecord::Migration[8.1]
  def change
    create_table :exposures do |t|
      t.references :user, null: false, foreign_key: true
      t.references :kanji, null: false, foreign_key: { to_table: :kanji }
      t.references :sentence, null: true, foreign_key: true
      t.string :kind, null: false
      t.datetime :occurred_at

      t.timestamps
    end

    add_index :exposures, %i[user_id kanji_id occurred_at]
  end
end
