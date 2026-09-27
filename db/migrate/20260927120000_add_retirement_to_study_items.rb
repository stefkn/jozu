class AddRetirementToStudyItems < ActiveRecord::Migration[8.1]
  def change
    # Retiring items from the due queue (tech plan §"Learning-loop review",
    # item 4): graduated_at is set automatically once an item is stable and
    # well-known; suspended_at is the manual "stop drilling this" button. Both
    # keep their rows (and mastery) so they still show on the Progress page and
    # can resume reviews later.
    add_column :user_kanji, :graduated_at, :datetime
    add_column :user_kanji, :suspended_at, :datetime
    add_column :user_words, :graduated_at, :datetime
    add_column :user_words, :suspended_at, :datetime
  end
end
