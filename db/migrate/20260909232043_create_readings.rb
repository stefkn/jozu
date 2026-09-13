class CreateReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :readings do |t|
      t.references :kanji, null: false, foreign_key: { to_table: :kanji }
      t.string :reading, null: false
      t.string :kind, null: false

      t.timestamps
    end

    add_index :readings, %i[kanji_id reading], unique: true
  end
end
