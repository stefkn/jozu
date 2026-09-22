module Learning
  # Plausible-by-construction multiple-choice distractors (concept §9, plan §8.3).
  #
  # Pools are per question type, broadened by fallback tiers so a plausible pool
  # almost never runs dry (a single-option question is pointless):
  #   kana_to_kanji     words sharing the target word's reading, else the same
  #                     first char / a radical relative, else words sharing any
  #                     of the target word's kanji characters
  #   sentence_to_kanji kanji sharing onyomi/kunyomi with the target kanji, else
  #                     visually similar (same radical / similar stroke count)
  #   kanji_to_meaning  meanings of visually similar kanji (same radical), else
  #                     meanings of homophone kanji (shared onyomi/kunyomi)
  #
  # Validity contract (property-tested): options unique, correct answer present
  # exactly once, distractors always come from a plausible pool. The generator
  # refuses to emit a question when even the broadest tier yields no distractor.
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
        kana_to_kanji_pool(target)
      when "sentence_to_kanji"
        kanji_confusion_pool(target)
      when "kanji_to_meaning"
        kanji_meanings_pool(target)
      else
        []
      end
    end

    # kana_to_kanji: words sharing the target word's reading, else words sharing
    # the first character, else visually similar kanji (same radical) at the same
    # position, else words sharing any of the target word's kanji characters
    # (plan §8.3, concept §9 "characters occurring in similar words"). Most words
    # have unique readings in the bank, so the fallback tiers keep the question
    # non-degenerate.
    def kana_to_kanji_pool(target)
      ids = Word.where(reading: target.reading).where.not(id: target.id).pluck(:id)

      first_char = target.surface[0]
      kanji = Kanji.find_by(character: first_char)
      similar_chars = if kanji&.radical_id
                        Kanji.where(radical_id: kanji.radical_id).where.not(id: kanji.id).pluck(:character)
      else
                        []
      end

      [ first_char, *similar_chars ].uniq.each do |char|
        ids += Word.where.not(id: target.id).where("surface LIKE ?", "#{char}%").pluck(:id)
      end

      target.surface.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }.each do |char|
        next unless (k = Kanji.find_by(character: char))

        ids += Word.joins(:word_kanji).where(word_kanji: { kanji_id: k.id })
                   .where.not(id: target.id).pluck(:id)
      end

      Word.where(id: ids.uniq).order(:frequency_rank).limit(20)
          .map { |w| [ w.id, w.surface ] }
    end

    def kanji_confusion_pool(target)
      # Sharing a reading (onyomi/kunyomi) or the same radical.
      reading_ids = target.readings.map(&:reading)
      ids = Reading.where(reading: reading_ids).where.not(kanji_id: target.id)
                   .pluck(:kanji_id).uniq
      ids += Kanji.where(radical_id: target.radical_id).where.not(id: target.id).pluck(:id) if target.radical_id

      # Visually similar by stroke count, only when the reading/radical tiers are
      # too thin (common kanji can lack imported readings and radicals).
      if ids.size < 10 && target.stroke_count
        ids += Kanji.where("abs(stroke_count - ?) <= ?", target.stroke_count, 1)
                    .where.not(id: target.id).pluck(:id)
      end

      Kanji.where(id: ids.uniq).order(:frequency_rank).limit(20)
           .map { |k| [ k.id, k.character ] }
    end

    def kanji_meanings_pool(target)
      ids = Kanji.where(radical_id: target.radical_id).where.not(id: target.id)
                 .where.not(meaning_summary: nil).pluck(:id)

      # Homophone confusion: kanji sharing an onyomi/kunyomi with a meaning.
      target.readings.each do |reading|
        ids += Reading.where(reading: reading.reading).where.not(kanji_id: target.id)
                      .joins(:kanji).where.not(kanji: { meaning_summary: nil })
                      .pluck(:kanji_id)
      end

      Kanji.where(id: ids.uniq).order(:frequency_rank).limit(20)
           .map { |k| [ k.id, k.meaning_summary ] }
    end
  end
end
