module Learning
  # "How much can I read?" metrics (concept §18, plan §13).
  #
  # Besides the aggregate counts, this exposes the concrete characters and
  # words behind them so the Progress page can list everything the learner
  # should be able to read/recognise:
  # - kanji grouped by bucket (known/learning/weak/unknown), each entry with
  #   its character, meaning, frequency rank and mastery;
  # - words split into readable (mastery >= known_threshold) vs. still
  #   learning, each entry with surface, reading, meaning and mastery.
  class Progress
    KanjiItem = Data.define(:character, :meaning_summary, :frequency_rank, :mastery_score, :bucket)
    WordItem = Data.define(:surface, :reading, :meaning, :frequency_rank, :mastery_score)

    Result = Data.define(:total_kanji, :covered, :known, :learning, :weak, :unknown,
                         :words_unlocked, :coverage_percent,
                         :known_kanji, :learning_kanji, :weak_kanji, :unknown_kanji,
                         :readable_words, :learning_words)

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
      grouped = { known: [], learning: [], weak: [], unknown: [] }
      top_kanji.each do |kanji|
        uk = rows[kanji.id]
        if uk.nil?
          buckets[:unknown] += 1
          grouped[:unknown] << KanjiItem.new(character: kanji.character,
                                            meaning_summary: kanji.meaning_summary,
                                            frequency_rank: kanji.frequency_rank,
                                            mastery_score: nil,
                                            bucket: :unknown)
        else
          covered += 1
          b = bucket(uk.mastery_score)
          buckets[b] += 1
          grouped[b] << KanjiItem.new(character: kanji.character,
                                     meaning_summary: kanji.meaning_summary,
                                     frequency_rank: kanji.frequency_rank,
                                     mastery_score: uk.mastery_score,
                                     bucket: b)
        end
      end

      readable_words = []
      learning_words = []
      user.user_words.includes(:word).to_a.each do |uw|
        item = WordItem.new(surface: uw.word.surface,
                            reading: uw.word.reading,
                            meaning: uw.word.meaning,
                            frequency_rank: uw.word.frequency_rank,
                            mastery_score: uw.mastery_score)
        if uw.mastery_score >= @config.known_threshold
          readable_words << item
        else
          learning_words << item
        end
      end
      readable_words.sort_by! { |w| w.frequency_rank || Float::INFINITY }
      learning_words.sort_by! { |w| w.frequency_rank || Float::INFINITY }

      words_unlocked = readable_words.size
      size = top_kanji.size
      coverage_percent = size.zero? ? 0.0 : (covered.to_f / size * 100).round(1)

      Result.new(total_kanji: size, covered:, known: buckets[:known],
                learning: buckets[:learning], weak: buckets[:weak], unknown: buckets[:unknown],
                words_unlocked:, coverage_percent:,
                known_kanji: grouped[:known], learning_kanji: grouped[:learning],
                weak_kanji: grouped[:weak], unknown_kanji: grouped[:unknown],
                readable_words:, learning_words:)
    end

    private

    def bucket(score)
      BUCKETS.find { |threshold, _| score >= threshold }&.last || :unknown
    end
  end
end
