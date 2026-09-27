module Learning
  # "What keeps tripping me up?" — the worst-performing items, worst first.
  #
  # A leech has seen enough reviews to judge (times_seen >= leech_min_reviews)
  # with a high failure rate (times_incorrect / times_seen >=
  # leech_min_failure_rate). Graduated items are out (they are known);
  # suspended items stay listed with a flag so they can be resumed. The view
  # builds links/actions from the payload — services stay route-free.
  class Leeches
    Leech = Data.define(:reviewable_type, :reviewable_id, :kind, :label, :sublabel,
                        :meaning, :seen, :incorrect, :failure_rate, :mastery,
                        :suspended, :character)
    Retired = Data.define(:reviewable_type, :reviewable_id, :kind, :label, :sublabel,
                          :meaning, :mastery, :graduated_at)

    def self.call(user, config: Learning.config)
      new(config:).call(user)
    end

    def self.graduated(user)
      new.graduated(user)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def call(user)
      scored = leech_rows(user).filter_map do |record|
        rate = failure_rate(record)
        next if rate < @config.leech_min_failure_rate

        [ rate, record ]
      end
      scored.sort_by { |(rate, record)| [ -rate, -record.times_incorrect ] }
            .first(@config.leech_limit)
            .map { |(_, record)| describe(record) }
    end

    def graduated(user)
      rows(user).select { |record| record.graduated_at.present? }
                .sort_by { |record| record.graduated_at }
                .reverse
                .map { |record| retire(record) }
    end

    private

    def leech_rows(user)
      rows(user).reject { |record| record.graduated_at.present? }
                .select { |record| record.times_seen >= @config.leech_min_reviews }
    end

    def rows(user)
      kanji = user.user_kanji.includes(:kanji).to_a
      words = user.user_words.includes(:word).to_a
      (kanji + words).reject { |record| NumberFilter.skip?(user, record) }
    end

    def failure_rate(record)
      return 0.0 if record.times_seen.zero?

      record.times_incorrect.to_f / record.times_seen
    end

    def describe(record)
      rate = failure_rate(record)
      case record
      when UserKanji
        Leech.new(reviewable_type: "UserKanji", reviewable_id: record.id, kind: :kanji,
                  label: record.kanji.character, sublabel: nil,
                  meaning: record.kanji.meaning_summary,
                  seen: record.times_seen, incorrect: record.times_incorrect,
                  failure_rate: rate,
                  mastery: record.mastery_score,
                  suspended: record.suspended_at.present?,
                  character: record.kanji.character)
      else
        Leech.new(reviewable_type: "UserWord", reviewable_id: record.id, kind: :word,
                  label: record.word.surface, sublabel: record.word.reading,
                  meaning: record.word.meaning,
                  seen: record.times_seen, incorrect: record.times_incorrect,
                  failure_rate: rate,
                  mastery: record.mastery_score,
                  suspended: record.suspended_at.present?,
                  character: nil)
      end
    end

    def retire(record)
      base = describe(record)
      Retired.new(reviewable_type: base.reviewable_type, reviewable_id: base.reviewable_id,
                  kind: base.kind, label: base.label, sublabel: base.sublabel,
                  meaning: base.meaning, mastery: base.mastery,
                  graduated_at: record.graduated_at)
    end
  end
end
