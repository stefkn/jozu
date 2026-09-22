module Learning
  # Renders a blanked sentence as HTML with <ruby> furigana on every kanji except
  # the blanked target. Readings prefer the LLM-generated, context-correct units
  # stored on sentences.furigana (see jozu:generate_furigana); without them it
  # falls back to the segmented word's kana reading, and a kanji not covered by
  # any segmented word to its primary reading.
  #
  # The furigana (<rt>) is hidden by default and shown on tap (recall practice,
  # not furigana reliance): every annotated word is wrapped in a tappable
  # <span class="kanji-tap"> carrying its reading (data-reading) and, when one
  # is stored on sentences.kanji_meanings, its context-aware English meaning
  # (data-meaning). The blanked target is also tappable: it reveals its reading
  # (the target word's reading, so the learner learns how the answer is read)
  # together with its meaning as a hint.
  class Furigana
    KANJI_RE = /[一-龯]/
    BLANK = "＿".freeze
    KUNYOMI = "kunyomi".freeze
    ONYOMI = "onyomi".freeze

    # Most representative reading of a bare kanji (kunyomi preferred, matching
    # the runtime fallback) — used to annotate the target kanji in
    # kanji_to_meaning questions.
    def self.primary_reading(kanji)
      rows = kanji.readings.to_a
      kun = rows.select { |r| r.kind == KUNYOMI }.filter_map { |r| normalize_reading(r.reading) }.first
      kun || rows.select { |r| r.kind == ONYOMI }.filter_map { |r| normalize_reading(r.reading) }.first
    end

    def self.normalize_reading(reading)
      reading.to_s.tr("ァ-ン", "ぁ-ん")
              .delete("ー")
              .split(/[．.。・\-]/)
              .max_by(&:length)
              .to_s
              .strip
    end

    def initialize(sentence, target_kanji)
      @sentence = sentence
      @target_char = target_kanji.character
    end

    # +prompt+ is the already-blanked sentence text; it must be the same char
    # length as the original so word spans still align. Words with a stored
    # context-aware meaning (sentences.kanji_meanings, aligned to the furigana
    # word units) are wrapped in tappable spans; the blanked target reveals its
    # word's reading and meaning as a hint on tap.
    def render(prompt)
      @chars = prompt.chars
      @length = @chars.size
      blank_positions = @chars.each_index.select { |i| @chars[i] == BLANK }
      all_spans = annotation_spans
      spans = all_spans.reject { |(st, en, _)| (st..en).any? { |i| blank_positions.include?(i) } }
      word_readings = dictionary_word_readings(all_spans)
      fallback = fallback_readings(all_spans)

      reading_at = {}
      spans.each { |(st, en, rd)| (st..en).each { |i| reading_at[i] = rd } }
      word_readings.each { |i, rd| reading_at[i] ||= rd }
      fallback.each { |i, rd| reading_at[i] ||= rd }
      target_readings(blank_positions).each { |i, rd| reading_at[i] ||= rd }

      meaning_at = {}
      meaning_spans.each { |u| (u["start"].to_i..u["end"].to_i).each { |i| meaning_at[i] = u["meaning"].to_s } }

      html = runs(reading_at, meaning_at).map { |(st, en, rd, mn)| emit(st, en, rd, mn) }.join
      html.html_safe
    end

    private

    def runs(reading_at, meaning_at)
      result = []
      i = 0
      while i < @length
        rd = reading_at[i]
        mn = meaning_at[i]
        j = i
        while j < @length && reading_at[j] == rd && meaning_at[j] == mn
          j += 1
        end
        result << [ i, j - 1, rd, mn ]
        i = j
      end
      result
    end

    def emit(start_pos, end_pos, reading, meaning)
      chars = @chars[start_pos..end_pos].join
      body = reading ? "<ruby>#{escape(chars)}<rt>#{escape(reading)}</rt></ruby>" : escape(chars)
      return body unless reading.present? || meaning.present?

      klass = chars.include?(BLANK) ? "kanji-tap is-blank" : "kanji-tap"
      attrs = []
      attrs << "data-reading=\"#{escape(reading)}\"" if reading.present?
      attrs << "data-meaning=\"#{escape(meaning)}\"" if meaning.present?
      "<span class=\"#{klass}\" #{attrs.join(' ')}>#{body}</span>"
    end

    def meaning_spans
      stored = @sentence.kanji_meanings
      return [] unless stored.present?

      stored
    end

    # Context-correct units from the LLM furigana pass take precedence over the
    # dictionary word-readings heuristic (which misreads suffix compounds like
    # 十日後 -> あと). Un-annotated sentences fall back to word_spans.
    def annotation_spans
      stored = @sentence.furigana
      return word_spans unless stored.present?

      stored.map { |u| [ u["start"].to_i, u["end"].to_i, u["reading"].to_s ] }
    end

    # Longest, non-overlapping words so irregular compounds (今日 -> きょう,
    # 上手 -> じょうず) keep their real reading instead of decomposed per-kanji
    # guesses. Words containing the blanked target kanji are the question itself,
    # so they are never annotated (a reading there would leak or mislead).
    def word_spans
      candidates = @sentence.sentence_words.includes(:word).filter_map do |sw|
        next unless sw.word && sw.start_position && sw.end_position
        next unless sw.word.surface.match?(KANJI_RE)
        next if sw.word.reading.blank?

        [ sw.start_position, sw.end_position, sw.word.reading.to_s ]
      end
      candidates.sort_by! { |(st, en, _)| -(en - st) }
      picked = []
      candidates.each do |(st, en, rd)|
        next if picked.any? { |(pst, pen, _)| !(pen < st || pst > en) }

        picked << [ st, en, rd ]
      end
      picked.sort_by! { |(st, _, _)| st }
    end

    # Kanji not covered by any stored unit or segmented word get the longest
    # dictionary word at that position (words table), so common compounds like
    # 好き -> すき keep their real reading instead of decomposing into the kanji's
    # primary reading (好 -> このむ). Only positions the dictionary can't explain
    # fall through to per-kanji primary readings.
    def dictionary_word_readings(spans)
      covered = spans.flat_map { |(st, en, _)| (st..en).to_a }
      DictionaryReadings.fill(@chars.join, covered:).flat_map { |(st, en, rd)| (st..en).map { |i| [ i, rd ] } }.to_h
    end

    # Readings for the blanked target word(s): stored context-correct units win,
    # otherwise the segmented word's reading. The target kanji is the answer, so
    # its furigana is intentionally suppressed from plain display but kept as a
    # tap-reveal hint so the learner learns the reading of the kanji they guess.
    def target_readings(blank_positions)
      result = {}
      annotation_spans.each do |(st, en, rd)|
        next unless rd.present?
        next unless (st..en).any? { |i| blank_positions.include?(i) }

        (st..en).each { |i| result[i] = rd }
      end
      @sentence.sentence_words.includes(:word).each do |sw|
        next unless sw.word && sw.word.reading.present?
        next unless sw.start_position && sw.end_position
        next unless (sw.start_position..sw.end_position).any? { |i| blank_positions.include?(i) }

        (sw.start_position..sw.end_position).each { |i| result[i] ||= sw.word.reading.to_s }
      end
      result
    end

    # Kanji with no segmented word (segmentation gaps) get the kanji's primary
    # reading as a last resort, so common single-kanji stems stay readable.
    def fallback_readings(spans)
      covered = spans.flat_map { |(st, en, _)| (st..en).to_a }
      positions = @chars.each_index.select do |i|
        kanji?(@chars[i]) && !covered.include?(i)
      end
      return {} if positions.empty?

      chars = positions.map { |i| @chars[i] }.uniq
      readings = Reading.joins(:kanji)
                        .where(kanji: { character: chars })
                        .to_a
                        .group_by { |r| r.kanji.character }
      positions.to_h { |i| [ i, primary_reading(readings[@chars[i]] || []) ] }.compact
    end

    def primary_reading(reading_rows)
      kun = rows_for(reading_rows, KUNYOMI).first
      kun || rows_for(reading_rows, ONYOMI).first
    end

    def rows_for(reading_rows, kind)
      reading_rows.select { |r| r.kind == kind }.map { |r| normalize(r.reading) }.reject(&:empty?)
    end

    def normalize(reading)
      self.class.normalize_reading(reading)
    end

    def kanji?(char)
      char.ord.between?(0x4e00, 0x9fff)
    end

    def escape(text)
      ERB::Util.html_escape(text)
    end
  end
end
