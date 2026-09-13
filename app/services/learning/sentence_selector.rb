module Learning
  # Sentence selection for sentence_to_kanji questions (concept §14, plan §8.4).
  #
  # Guarantees "the target kanji is the difficult part": every other kanji in the
  # sentence must be frequent or already known by the learner. Candidates are
  # scored by target-word frequency, comprehension (knownness of the other words)
  # and novelty (not recently shown for this kanji).
  class SentenceSelector
    MAX_SENTENCE_LENGTH = 40
    MAX_OTHER_KANJI_RANK = 2000

    def self.select(user, kanji:, exclude: [], random: Random.new, config: Learning.config)
      new(random:, config:).select(user, kanji:, exclude:)
    end

    def initialize(random: Random.new, config: Learning.config)
      @random = random
      @config = config
      @leverage = LeverageCalculator.new(config:)
      @segmenter = Segmentation::LongestMatch.build(Word.pluck(:surface))
    end

    # @return [Sentence, nil] the best sentence for the target kanji, or nil.
    def select(user, kanji:, exclude: [])
      candidates = candidate_sentences(kanji)
      return nil if candidates.empty?

      scored = candidates.filter_map { |s| score(s, user, kanji, exclude) }
      return nil if scored.empty?

      scored.max_by { |sentence, _| sentence }&.last
    end

    private

    def candidate_sentences(kanji)
      word_ids = Word.joins(:word_kanji).where(word_kanji: { kanji_id: kanji.id }).pluck(:id)
      return [] if word_ids.empty?

      Sentence.joins(:sentence_words)
              .where(sentence_words: { word_id: word_ids })
              .where("length(japanese) <= ?", MAX_SENTENCE_LENGTH)
              .distinct
              .limit(100)
              .to_a
    end

    # Returns [score, sentence] or nil when the sentence fails the difficulty gate.
    def score(sentence, user, kanji, exclude)
      return nil if exclude.include?(sentence.id)
      return nil if ExposureRecorder.recently_seen?(user, kanji, sentence)

      other_kanji = other_kanji_in(sentence, kanji)
      return nil unless all_easy?(other_kanji, user)

      target_word = target_word(sentence, kanji)
      return nil unless target_word

      target_word_frequency = frequency_factor(target_word)
      comprehension = comprehension_score(sentence, target_word, user)
      novelty = 1.0 / (1.0 + ExposureRecorder.seen_count(user, kanji, sentence))

      [ target_word_frequency * comprehension * novelty, sentence ]
    end

    def other_kanji_in(sentence, target_kanji)
      kanji_chars = sentence.japanese.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }
      kanji_chars.reject { |c| c == target_kanji.character }.uniq
    end

    def all_easy?(kanji_chars, user)
      kanji_chars.all? do |char|
        kanji = Kanji.find_by(character: char)
        next true if kanji.nil?
        next true if known_by_user?(kanji, user)
        next true if kanji.frequency_rank && kanji.frequency_rank <= MAX_OTHER_KANJI_RANK

        false
      end
    end

    def known_by_user?(kanji, user)
      uk = UserKanji.find_by(user_id: user.id, kanji_id: kanji.id)
      uk && uk.mastery_score > @config.known_threshold
    end

    def target_word(sentence, kanji)
      words = Word.joins(:word_kanji).where(word_kanji: { kanji_id: kanji.id })
      sentence.sentence_words.map(&:word).find { |w| words.map(&:id).include?(w.id) }
    end

    def frequency_factor(word)
      return 0.5 if word.frequency_rank.nil?

      max_raw = 1.0 / Math.log2(3.0)
      raw = 1.0 / Math.log2(word.frequency_rank + 2)
      (raw / max_raw).clamp(0.0, 1.0)
    end

    def comprehension_score(sentence, target_word, user)
      other_words = sentence.sentence_words.map(&:word).reject { |w| w.id == target_word.id }
      return 1.0 if other_words.empty?

      other_words.sum { |w| @leverage.word_weight(w, user) } / other_words.size
    end
  end
end
