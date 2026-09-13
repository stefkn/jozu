class CreateWords < ActiveRecord::Migration[8.1]
  def change
    create_table :words do |t|
      t.string :surface, null: false
      t.string :reading, null: false
      t.integer :frequency_rank
      t.string :jlpt_level
      t.text :meaning, null: false
      t.string :part_of_speech

      t.timestamps
    end

    add_index :words, :surface, unique: true
    add_index :words, :reading
    add_index :words, :frequency_rank
  end
end
