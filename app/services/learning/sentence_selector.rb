module Learning
  # Sentence selection for sentence_to_kanji questions (concept §14, plan §8.4).
  #
  # Guarantees "the target kanji is the difficult part": every other kanji in the
  # sentence must be frequent or already known by the learner. Candidates are
  # scored by target-word frequency, comprehension (knownness of the other words)
  # and novelty (not recently shown for this kanji).
  #
  # All lookups for the candidate batch are preloaded once per select call, so
  # scoring stays query-light even on a ~5k-sentence bank.
  class SentenceSelector
    MAX_SENTENCE_LENGTH = 40
    MAX_OTHER_KANJI_RANK = 2000
    CANDIDATE_LIMIT = 100

    def self.select(user, kanji:, exclude: [], random: Random.new, config: Learning.config)
      new(random:, config:).select(user, kanji:, exclude:)
    end

    def initialize(random: Random.new, config: Learning.config)
      @random = random
      @config = config
    end

    # @return [Sentence, nil] the best sentence for the target kanji, or nil.
    def select(user, kanji:, exclude: [])
      candidates = candidate_sentences(kanji)
      return nil if candidates.empty?

      context = build_context(user, kanji, candidates, exclude)
      scored = candidates.filter_map { |s| score(s, kanji, context) }
      return nil if scored.empty?

      scored.max_by { |sentence, _| sentence }&.last
    end

    private

    # Eager-loads each candidate's words so scoring never queries per candidate.
    def candidate_sentences(kanji)
      word_ids = Word.joins(:word_kanji).where(word_kanji: { kanji_id: kanji.id }).pluck(:id)
      return [] if word_ids.empty?

      Sentence.joins(:sentence_words)
              .where(sentence_words: { word_id: word_ids })
              .where("length(japanese) <= ?", MAX_SENTENCE_LENGTH)
              .includes(sentence_words: :word)
              .distinct
              .limit(CANDIDATE_LIMIT)
              .to_a
    end

    def build_context(user, kanji, candidates, exclude)
      sentence_ids = candidates.map(&:id)
      {
        exclude: exclude.to_set,
        kanji_ranks: Kanji.pluck(:character, :frequency_rank).to_h,
        known_kanji: known_kanji_ids(user),
        kanji_words: Word.joins(:word_kanji).where(word_kanji: { kanji_id: kanji.id }).pluck(:id).to_set,
        recent_sentences: Exposure.where(user:, kanji:, sentence_id: sentence_ids, kind: "sentence",
                                         occurred_at: @config.recent_exposure_window.ago..Time.current)
                                  .pluck(:sentence_id).to_set,
        seen_counts: Exposure.where(user:, kanji:, sentence_id: sentence_ids).group(:sentence_id).count,
        word_mastery: word_mastery(user, candidates)
      }
    end

    def known_kanji_ids(user)
      UserKanji.where(user_id: user.id).where("mastery_score > ?", @config.known_threshold)
               .pluck(:kanji_id).to_set
    end

    def word_mastery(user, candidates)
      word_ids = candidates.flat_map { |s| s.sentence_words.map(&:word_id) }.uniq
      UserWord.where(user_id: user.id, word_id: word_ids).pluck(:word_id, :mastery_score).to_h
    end

    # Returns [score, sentence] or nil when the sentence fails the difficulty gate.
    def score(sentence, kanji, context)
      return nil if context[:exclude].include?(sentence.id)
      return nil if context[:recent_sentences].include?(sentence.id)

      other_kanji = other_kanji_in(sentence, kanji)
      return nil unless all_easy?(other_kanji, context)

      target_word = target_word(sentence, context[:kanji_words])
      return nil unless target_word

      target_word_frequency = frequency_factor(target_word)
      comprehension = comprehension_score(sentence, target_word, context[:word_mastery])
      novelty = 1.0 / (1.0 + (context[:seen_counts][sentence.id] || 0))

      [ target_word_frequency * comprehension * novelty, sentence ]
    end

    def other_kanji_in(sentence, target_kanji)
      kanji_chars = sentence.japanese.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }
      kanji_chars.reject { |c| c == target_kanji.character }.uniq
    end

    def all_easy?(kanji_chars, context)
      kanji_chars.all? do |char|
        rank = context[:kanji_ranks][char]
        next true if rank.nil? # not in the bank -> outside the difficulty gate
        next true if rank <= MAX_OTHER_KANJI_RANK

        # Only reachable for kanji beyond the frequency band: known beats rare.
        kanji = Kanji.find_by(character: char)
        kanji && context[:known_kanji].include?(kanji.id)
      end
    end

    def target_word(sentence, kanji_words)
      sentence.sentence_words.map(&:word).find { |w| kanji_words.include?(w.id) }
    end

    def frequency_factor(word)
      return 0.5 if word.frequency_rank.nil?

      max_raw = 1.0 / Math.log2(3.0)
      raw = 1.0 / Math.log2(word.frequency_rank + 2)
      (raw / max_raw).clamp(0.0, 1.0)
    end

    def comprehension_score(sentence, target_word, word_mastery)
      other_words = sentence.sentence_words.map(&:word).reject { |w| w.id == target_word.id }
      return 1.0 if other_words.empty?

      other_words.sum { |w| word_mastery[w.id] || prior_by_frequency(w.frequency_rank) } / other_words.size
    end

    # Unseen word: frequency prior that decays with rank (plan §7), matching
    # LeverageCalculator.word_weight for unseen words.
    def prior_by_frequency(rank)
      return 0.1 if rank.nil?

      0.5 * Math.exp(-rank / 2000.0)
    end
  end
end
