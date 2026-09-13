module Learning
  # Vocabulary-leverage of a kanji (concept §6.2, plan §7): how much value the
  # learner gets from learning K, weighted by how known the words containing it are.
  class LeverageCalculator
    def self.call(kanji, user, config: Learning.config)
      new(config:).call(kanji, user)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    # Sum of word weights, normalized by the word count so the result is in [0, 1].
    def leverage_score(kanji, user)
      words = words_containing(kanji)
      return 0.0 if words.empty?

      sum = words.sum { |w| word_weight(w, user) }
      (sum / words.size).clamp(0.0, 1.0)
    end

    # "Learn 必 — unlocks N words you already know."
    def unlock_count(kanji, user)
      words_containing(kanji).count { |w| word_weight(w, user) >= @config.known_threshold }
    end

    def word_weight(word, user)
      known = UserWord.find_by(user_id: user.id, word_id: word.id)
      known ? known.mastery_score : prior_by_frequency(word.frequency_rank)
    end

    private

    def words_containing(kanji)
      Word.joins(:word_kanji).where(word_kanji: { kanji_id: kanji.id })
    end

    # Unseen word: frequency prior that decays with rank (plan §7).
    def prior_by_frequency(rank)
      return 0.1 if rank.nil?

      0.5 * Math.exp(-rank / 2000.0)
    end
  end
end
