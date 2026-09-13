module Learning
  # "How much can I read?" metrics (concept §18, plan §13).
  class Progress
    Result = Data.define(:total_kanji, :covered, :known, :learning, :weak, :unknown,
                         :words_unlocked, :coverage_percent)

    BUCKETS = [
      [ 0.75, :known ],
      [ 0.4, :learning ],
      [ 0.2, :weak ]
    ].freeze

    def self.call(user, top_n: 500, config: Learning.config)
      new(config:).call(user, top_n:)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def call(user, top_n: 500)
      top_kanji = Kanji.where.not(frequency_rank: nil).order(:frequency_rank).limit(top_n)
      rows = user.user_kanji.to_a.index_by(&:kanji_id)

      buckets = Hash.new(0)
      covered = 0
      top_kanji.each do |kanji|
        uk = rows[kanji.id]
        if uk.nil?
          buckets[:unknown] += 1
        else
          covered += 1
          buckets[bucket(uk.mastery_score)] += 1
        end
      end

      words_unlocked = user.user_words.count { |uw| uw.mastery_score >= @config.known_threshold }
      coverage_percent = (covered.to_f / top_kanji.size * 100).round(1)

      Result.new(total_kanji: top_kanji.size, covered:, known: buckets[:known],
                learning: buckets[:learning], weak: buckets[:weak], unknown: buckets[:unknown],
                words_unlocked:, coverage_percent:)
    end

    private

    def bucket(score)
      BUCKETS.find { |threshold, _| score >= threshold }&.last || :unknown
    end
  end
end
