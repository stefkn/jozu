module Learning
  # Plausible-by-construction multiple-choice distractors (concept §9, plan §8.3).
  #
  # Pools are per question type:
  #   kana_to_kanji     words sharing the target word's reading
  #   sentence_to_kanji kanji sharing onyomi/kunyomi with the target kanji, or
  #                     visually similar (same radical / similar stroke count)
  #   kanji_to_meaning  meanings of visually similar kanji (same radical)
  #
  # Validity contract (property-tested): options unique, correct answer present
  # exactly once, distractors always come from a plausible pool.
  class DistractorSelector
    def self.select_for(question_type:, target:, exclude_ids: [], count: 3, random: Random.new)
      new(random:).select_for(question_type:, target:, exclude_ids:, count:)
    end

    def initialize(random: Random.new)
      @random = random
    end

    # @return [Array<[Integer, String]>] distractor (id, label) pairs.
    def select_for(question_type:, target:, exclude_ids: [], count: 3)
      pool = candidate_pool(question_type, target)
      candidates = pool.reject { |id, _| exclude_ids.include?(id) }
                       .uniq { |id, _| id }
                       .shuffle(random: @random)
                       .first(count)

      candidates.map { |id, label| [ id, label ] }
    end

    private

    def candidate_pool(question_type, target)
      case question_type
      when "kana_to_kanji"
        words_sharing_reading(target)
      when "sentence_to_kanji"
        kanji_confusion_pool(target)
      when "kanji_to_meaning"
        kanji_meanings_pool(target)
      else
        []
      end
    end

    def words_sharing_reading(target)
      Word.where(reading: target.reading).where.not(id: target.id)
          .limit(20).map { |w| [ w.id, w.surface ] }
    end

    def kanji_confusion_pool(target)
      # Sharing a reading (onyomi/kunyomi) or the same radical.
      reading_ids = target.readings.map(&:reading)
      ids = Reading.where(reading: reading_ids).where.not(kanji_id: target.id)
                   .pluck(:kanji_id).uniq
      ids += Kanji.where(radical_id: target.radical_id).where.not(id: target.id).pluck(:id) if target.radical_id

      Kanji.where(id: ids.uniq).order(:frequency_rank).limit(20)
           .map { |k| [ k.id, k.character ] }
    end

    def kanji_meanings_pool(target)
      Kanji.where(radical_id: target.radical_id).where.not(id: target.id)
           .where.not(meaning_summary: nil).order(:frequency_rank).limit(20)
           .map { |k| [ k.id, k.meaning_summary ] }
    end
  end
end
