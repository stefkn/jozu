module Learning
  # Personalized candidate ranking (concept §6, plan §7).
  #
  #   priority = frequency_score * leverage_score * uncertainty
  #
  # personal_relevance and prerequisite_bonus default to 1.0 in Plan A and slot in
  # as extra multiplicative factors in Plan B.
  class PriorityCalculator
    Result = Data.define(:kanji, :priority, :frequency_score, :leverage_score, :uncertainty)

    def self.call(user, kanji:, config: Learning.config)
      new(config:).call(user, kanji:)
    end

    def initialize(config: Learning.config)
      @config = config
      @leverage = LeverageCalculator.new(config:)
    end

    def call(user, kanji:)
      freq = frequency_score(kanji)
      lev = @leverage.leverage_score(kanji, user)
      unc = uncertainty(user_kanji_for(user, kanji))

      priority = freq * lev * unc
      Result.new(kanji:, priority:, frequency_score: freq, leverage_score: lev, uncertainty: unc)
    end

    # Batched fresh-kanji ranking (plan §7). Loading every unseen kanji and scoring
    # it via per-kanji queries (WordKanji join + UserWord lookups) balloons to a
    # few thousand queries once the bank passes ~1k kanji; preload all the lookups
    # in a handful of queries and score in memory.
    def top_unseen(user, limit:)
      seen_ids = user.user_kanji.pluck(:kanji_id)
      candidates = Kanji.where.not(id: seen_ids)
      candidates = candidates.where.not(character: Kanji::NUMBER_KANJI) if user.skip_number_kanji?
      candidates = candidates.order(:frequency_rank).to_a

      user_kanji_by_id = UserKanji.where(user_id: user.id).index_by(&:kanji_id)
      user_word_by_id = UserWord.where(user_id: user.id).index_by(&:word_id)
      word_kanji_by_id = WordKanji.where(kanji_id: candidates.map(&:id)).group_by(&:kanji_id)
      words_by_id = Word.where(id: word_kanji_by_id.values.flatten.map(&:word_id).uniq).index_by(&:id)

      ranked = candidates.filter_map do |k|
        words = (word_kanji_by_id[k.id] || []).filter_map { |wk| words_by_id[wk.word_id] }
        priority = frequency_score(k) * leverage_for(words, user_word_by_id) * uncertainty(user_kanji_by_id[k.id])
        next if priority.zero?

        [ priority, k.frequency_rank.to_i, k ]
      end
      ranked.sort_by { |priority, rank, _| [ -priority, rank ] }
            .first(limit)
            .map { |_, _, kanji| kanji }
    end

    private

    # Same average word weight LeverageCalculator computes, from preloaded state.
    def leverage_for(words, user_word_by_id)
      return 0.0 if words.empty?

      sum = words.sum { |w| user_word_by_id[w.id]&.mastery_score || prior_by_frequency(w.frequency_rank) }
      (sum / words.size).clamp(0.0, 1.0)
    end

    def prior_by_frequency(rank)
      return 0.1 if rank.nil?

      0.5 * Math.exp(-rank / 2000.0)
    end

    # 1/log2(rank + 2), normalized so rank 1 scores 1.0 (plan §7).
    def frequency_score(kanji)
      return 0.0 if kanji.frequency_rank.nil?

      max_raw = 1.0 / Math.log2(3.0)
      raw = 1.0 / Math.log2(kanji.frequency_rank + 2)
      (raw / max_raw).clamp(0.0, 1.0)
    end

    # Smoothed correct rate shaped to peak at p = 0.5 (plan §7).
    def uncertainty(user_kanji)
      return 0.6 if user_kanji.nil? || user_kanji.times_seen.zero?

      p = (user_kanji.times_correct + 1.0) / (user_kanji.times_seen + 2.0)
      4.0 * p * (1.0 - p)
    end

    def user_kanji_for(user, kanji)
      UserKanji.find_by(user_id: user.id, kanji_id: kanji.id)
    end
  end
end
