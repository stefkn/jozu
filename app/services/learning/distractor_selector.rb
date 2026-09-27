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
  #
  # When `user:` is given, the user's own historical confusers for this target
  # (Learning::ConfusionPairs) are preferred over static-pool options, so a
  # repeated confusion gets deliberate contrast instead of a random distractor.
  class DistractorSelector
    def self.select_for(question_type:, target:, exclude_ids: [], count: 3, random: Random.new, user: nil)
      new(random:).select_for(question_type:, target:, exclude_ids:, count:, user:)
    end

    def initialize(random: Random.new)
      @random = random
    end

    # @return [Array<[Integer, String]>] distractor (id, label) pairs.
    def select_for(question_type:, target:, exclude_ids: [], count: 3, user: nil)
      pool = candidate_pool(question_type, target)
      static = pool.reject { |id, _| exclude_ids.include?(id) }
                   .uniq { |id, _| id }
                   .shuffle(random: @random)
                   .first(count)
      return static if user.nil?

      prefer_confusers(user, question_type, target, static, exclude_ids, count)
    end

    private

    # Historical confusers first (kept only when they still resolve to a real
    # option), static-pool options fill the remainder. Confusers resolve
    # directly against the bank rather than through the current static pool:
    # pools evolve as the bank grows, but a past confusion stays
    # learner-plausible by definition.
    def prefer_confusers(user, question_type, target, static, exclude_ids, count)
      confusers = Learning::ConfusionPairs.confusers_for(
        user, question_type:, target_id: target.id, limit: count
      ).filter_map do |chosen_id|
        next if exclude_ids.map(&:to_s).include?(chosen_id.to_s)

        label = confuser_label(question_type, target, chosen_id)
        next if label.blank?

        [ chosen_id, label ]
      end.uniq { |id, _| id.to_s }

      merged = (confusers + static.reject { |id, _| confusers.any? { |cid, _| cid.to_s == id.to_s } })
      # Readings are not unique across words; de-duplicate labels so two
      # buttons never show the same kana.
      merged = merged.uniq(&:last) if question_type == "kanji_to_reading"
      merged.first(count)
    end

    def confuser_label(question_type, target, chosen_id)
      case question_type
      when "sentence_to_kanji"
        Kanji.find_by(id: chosen_id)&.character
      when "kanji_to_meaning"
        Kanji.find_by(id: chosen_id)&.meaning_summary
      when "kana_to_kanji"
        Word.find_by(id: chosen_id)&.surface
      when "kanji_to_reading"
        reading = Word.find_by(id: chosen_id)&.reading
        reading if reading.present? && reading != target.reading
      end
    end

    def candidate_pool(question_type, target)
      case question_type
      when "kana_to_kanji"
        kana_to_kanji_pool(target)
      when "kanji_to_reading"
        kanji_to_reading_pool(target)
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
      confusable_words(target).map { |w| [ w.id, w.surface ] }
    end

    # kanji_to_reading: the same confusable words as kana_to_kanji, but labelled
    # by reading. Words sharing the target's reading are dropped (they would
    # render a second correct button), and labels are de-duplicated (readings,
    # unlike surfaces, are not unique).
    def kanji_to_reading_pool(target)
      seen = Set.new([ target.reading ])
      confusable_words(target).filter_map do |w|
        next if w.reading.blank?
        next unless seen.add?(w.reading)

        [ w.id, w.reading ]
      end
    end

    def confusable_words(target)
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

      Word.where(id: ids.uniq).order(:frequency_rank).limit(20).to_a
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
