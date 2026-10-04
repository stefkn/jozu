module Learning
  # Minimal reading stream (improvement #6, concept §17): 3-5 short,
  # high-comprehension sentences for contextual exposure.
  #
  # Reuses the Furigana tap-reveal renderer and the exposures table. Sentences
  # are scored by comprehension (mean knownness of their words) and novelty
  # (not recently read), so the target is fluent reading, not new-kanji drill.
  class ReadingPassage
    MAX_SENTENCE_LENGTH = 40
    CANDIDATE_LIMIT = 500

    Passage = Data.define(:sentence, :html)

    def self.select(user, count: nil, config: Learning.config)
      new(config:).select(user, count: count || config.reading_sentence_count)
    end

    def self.available?(user, config: Learning.config)
      new(config:).available?(user)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def select(user, count:)
      candidates = candidate_sentences(user)
      return [] if candidates.empty?

      context = build_context(user, candidates)
      scored = candidates.filter_map { |s| score(s, context) }
      top = scored.sort_by { |(score_value, _)| -score_value }.first(count).map(&:last)
      top.map { |sentence| Passage.new(sentence:, html: furigana_html(sentence)) }
    end

    def available?(user)
      recent = recent_read_sentence_ids(user)
      scope = Sentence.where("length(japanese) <= ?", MAX_SENTENCE_LENGTH)
      scope = scope.where.not(id: recent.to_a) if recent.any?
      scope.exists?
    end

    private

    def candidate_sentences(user)
      recent = recent_read_sentence_ids(user)
      scope = Sentence.where("length(japanese) <= ?", MAX_SENTENCE_LENGTH)
                      .includes(sentence_words: :word)
                      .order("length(japanese) ASC")
                      .limit(CANDIDATE_LIMIT)
      rows = scope.to_a
      rows = rows.reject { |s| recent.include?(s.id) }
      rows.empty? ? scope.to_a : rows
    end

    def build_context(user, candidates)
      sentence_ids = candidates.map(&:id)
      word_ids = candidates.flat_map { |s| s.sentence_words.map(&:word_id) }.uniq
      {
        word_mastery: UserWord.where(user_id: user.id, word_id: word_ids).pluck(:word_id, :mastery_score).to_h,
        seen_counts: Exposure.where(user_id: user.id, sentence_id: sentence_ids, kind: "reading")
                             .group(:sentence_id).count
      }
    end

    # Returns [score, sentence]; comprehension dominates, novelty breaks ties.
    def score(sentence, context)
      words = sentence.sentence_words.map(&:word).compact
      return nil if words.empty?

      comprehension = words.sum { |w| context[:word_mastery][w.id] || prior_by_frequency(w.frequency_rank) } / words.size
      novelty = 1.0 / (1.0 + (context[:seen_counts][sentence.id] || 0))
      [ comprehension * 0.8 + novelty * 0.2, sentence ]
    end

    def prior_by_frequency(rank)
      return 0.1 if rank.nil?

      0.5 * Math.exp(-rank / 2000.0)
    end

    def recent_read_sentence_ids(user)
      Exposure.where(user_id: user.id, kind: "reading")
              .where("occurred_at >= ?", @config.recent_exposure_window.ago)
              .where.not(sentence_id: nil)
              .pluck(:sentence_id).to_set
    end

    def furigana_html(sentence)
      Learning::OptionDetails.furigana_html(sentence)
    rescue StandardError
      ERB::Util.html_escape(sentence.japanese).to_s
    end
  end
end
