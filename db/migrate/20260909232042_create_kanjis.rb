class CreateKanjis < ActiveRecord::Migration[8.1]
  def change
    create_table :kanji do |t|
      t.string :character, null: false
      t.string :unicode_codepoint
      t.integer :grade
      t.integer :frequency_rank
      t.integer :stroke_count
      t.string :meaning_summary
      t.integer :radical_id

      t.timestamps
    end

    add_index :kanji, :character, unique: true
  end
end
