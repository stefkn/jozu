class CreateWordKanjis < ActiveRecord::Migration[8.1]
  def change
    create_table :word_kanji do |t|
      t.references :word, null: false, foreign_key: true
      t.references :kanji, null: false, foreign_key: { to_table: :kanji }
      t.integer :position, null: false

      t.timestamps
    end

    add_index :word_kanji, %i[word_id kanji_id], unique: true
  end
end
