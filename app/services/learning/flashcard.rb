module Learning
  # Flashcard for the onboarding diagnostic: the learner sees the kanji form
  # (front) and taps to reveal the reading (back), then self-assesses.
  Flashcard = Data.define(:token, :word_id, :front, :back)
end
