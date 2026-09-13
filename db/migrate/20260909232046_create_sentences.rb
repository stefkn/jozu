class CreateSentences < ActiveRecord::Migration[8.1]
  def change
    create_table :sentences do |t|
      t.text :japanese, null: false
      t.text :translation
      t.integer :difficulty
      t.string :source, null: false
      t.string :external_id
      t.string :generation_version

      t.timestamps
    end

    add_index :sentences, :external_id
  end
end
