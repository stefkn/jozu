class CreateSentenceWords < ActiveRecord::Migration[8.1]
  def change
    create_table :sentence_words do |t|
      t.references :sentence, null: false, foreign_key: true
      t.references :word, null: false, foreign_key: true
      t.integer :start_position
      t.integer :end_position

      t.timestamps
    end

    add_index :sentence_words, %i[sentence_id word_id], unique: true
  end
end
