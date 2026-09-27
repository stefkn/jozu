class AddAnswerTrackingToReviews < ActiveRecord::Migration[8.1]
  def change
    # Confusion-network substrate (tech plan §"Learning-loop review 2026-09-25",
    # item 1): knowing *which* option was chosen on a wrong answer lets us mine
    # (correct, chosen) confusion pairs. Nullable so pre-existing and diagnostic
    # rows stay valid.
    add_column :reviews, :answer_id, :string
    add_column :reviews, :correct_option_id, :string
  end
end
