module Learning
  # Shared "skip this reviewable?" logic for users who opt out of number kanji
  # (user setting "skip_number_kanji"). New-kanji selection, the due queue, the
  # diagnostic, and the home summary all route through this so a skipped kanji
  # never surfaces anywhere.
  module NumberFilter
    module_function

    def skip?(user, reviewable)
      return false unless user.skip_number_kanji?

      kanji = kanji_for(reviewable)
      kanji && Kanji.number?(kanji.character)
    end

    def kanji_for(reviewable)
      return reviewable.kanji if reviewable.respond_to?(:kanji)

      reviewable.word.kanji.first if reviewable.respond_to?(:word)
    end
  end
end
