class AddKanjiMeaningsToSentences < ActiveRecord::Migration[8.1]
  def change
    add_column :sentences, :kanji_meanings, :jsonb
  end
end
