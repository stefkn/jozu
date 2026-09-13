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

    def top_unseen(user, limit:)
      seen_ids = user.user_kanji.pluck(:kanji_id)
      candidates = Kanji.where.not(id: seen_ids).order(:frequency_rank)
      results = candidates.map { |k| call(user, kanji: k) }
      results.reject { |r| r.priority.zero? }
             .sort_by { |r| [ -r.priority, r.kanji.frequency_rank.to_i ] }
             .first(limit)
             .map(&:kanji)
    end

    private

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
