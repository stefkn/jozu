class RelaxRadicalsKey < ActiveRecord::Migration[8.1]
  def up
    remove_index :radicals, :number
    change_column_null :radicals, :number, true
    add_index :radicals, :number
  end

  def down
    remove_index :radicals, :number
    change_column_null :radicals, :number, false
    add_index :radicals, :number, unique: true
  end
end
