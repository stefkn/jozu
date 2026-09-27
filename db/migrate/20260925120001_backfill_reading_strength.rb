class BackfillReadingStrength < ActiveRecord::Migration[8.1]
  def up
    # The kanji_to_reading question type (tech plan §"Learning-loop review
    # 2026-09-25", item 2) starts writing reading_strength, which was always 0.0
    # before. Seed existing rows at half their recognition strength so the new
    # dimension calibrates with ~1 reading question per kanji instead of
    # flooding every due review, and recompute the stored mastery with the same
    # weights as UserKanji#recompute_mastery (0.5/0.2/0.3).
    execute(<<~SQL.squish)
      UPDATE user_kanji
      SET reading_strength = recognition_strength * 0.5,
          mastery_score = ROUND(
            (0.5 * recognition_strength + 0.2 * (recognition_strength * 0.5) + 0.3 * context_strength)::numeric, 4
          )::float
      WHERE reading_strength = 0.0
    SQL
  end

  def down
    # Keep the column values; only the mastery recomputation is reverted.
    execute(<<~SQL.squish)
      UPDATE user_kanji
      SET mastery_score = ROUND(
        (0.5 * recognition_strength + 0.3 * context_strength)::numeric, 4
      )::float
    SQL
  end
end
