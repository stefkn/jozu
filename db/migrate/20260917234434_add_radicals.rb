class AddRadicals < ActiveRecord::Migration[8.1]
  def change
    create_table :radicals do |t|
      t.integer :number, null: false
      t.string :character, null: false
      t.string :name, null: false
      t.integer :stroke_count
      t.timestamps

      t.index :number, unique: true
      t.index :character, unique: true
    end

    change_column :kanji, :radical_id, :bigint
    add_foreign_key :kanji, :radicals
    add_index :kanji, :radical_id
  end
end
