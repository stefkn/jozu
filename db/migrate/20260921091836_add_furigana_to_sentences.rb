class AddFuriganaToSentences < ActiveRecord::Migration[8.1]
  def change
    add_column :sentences, :furigana, :jsonb
  end
end
