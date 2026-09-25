module Learning
  # Study details for each answer option on "Choose the kanji" questions
  # (kana_to_kanji + sentence_to_kanji). Rendered hidden with the question and
  # revealed by the quiz controller after the learner picks an answer, so the
  # info never gives away the answer up front.
  #
  # - sentence_to_kanji options are kanji: common readings only (de-duplicated,
  #   ranked by word frequency), English meaning, example sentences with furigana.
  # - kana_to_kanji options are words: word reading + meaning, the kanji inside
  #   the word (each with ranked readings + meaning), example sentences.
  class OptionDetails
    EXAMPLE_LIMIT = 2
    RANK_WORD_LIMIT = 15
    COMMON_READING_COUNT = 2

    ReadingItem = Data.define(:reading, :kind)
    Example = Data.define(:html, :translation)
    KanjiBrief = Data.define(:character, :meaning, :readings)
    KanjiOption = Data.define(:option_id, :character, :meaning, :readings, :examples)
    WordOption = Data.define(:option_id, :surface, :reading, :meaning, :kanji, :examples)

    # Small kana -> large kana so onyomi like けつ match words like けってい.
    SMALL_KANA = "ぁぃぅぇぉゃゅょっゎゕゖ"
    LARGE_KANA = "あいうえおやゆよつわか"

    def self.for_question(question, example_limit: EXAMPLE_LIMIT)
      case question.question_type
      when "sentence_to_kanji" then for_kanji_options(question, example_limit:)
      when "kana_to_kanji" then for_word_options(question, example_limit:)
      else []
      end
    end

    def self.for_kanji_options(question, example_limit: EXAMPLE_LIMIT)
      ids = question.options.keys.map { |id| id.to_s }
      kanjis = Kanji.where(id: ids).includes(:readings, :words).index_by { |k| k.id.to_s }
      ids.filter_map do |option_id|
        kanji = kanjis[option_id]
        next if kanji.nil?

        words_sorted = sorted_words(kanji.words)
        KanjiOption.new(
          option_id:,
          character: kanji.character,
          meaning: kanji.meaning_summary,
          readings: common_readings(kanji, words_sorted),
          examples: examples_for_kanji(kanji, words_sorted, exclude_sentence_id: question.sentence_id,
                                       limit: example_limit)
        )
      end
    end

    def self.for_word_options(question, example_limit: EXAMPLE_LIMIT)
      ids = question.options.keys.map { |id| id.to_s }
      words = Word.where(id: ids).includes(kanji: [ :readings, :words ]).index_by { |w| w.id.to_s }
      ids.filter_map do |option_id|
        word = words[option_id]
        next if word.nil?

        kanji_briefs = word.kanji.map do |k|
          k_words = k.association_cached?(:words) ? sorted_words(k.words) : sorted_words(k.words.to_a)
          KanjiBrief.new(character: k.character, meaning: k.meaning_summary,
                         readings: common_readings(k, k_words))
        end
        WordOption.new(
          option_id:,
          surface: word.surface,
          reading: word.reading,
          meaning: word.meaning,
          kanji: kanji_briefs,
          examples: examples_for_word(word, limit: example_limit)
        )
      end
    end

    # Common readings for study notes: de-duplicated, then trimmed to the
    # readings actually used by frequent words (word-frequency ranking: the
    # readings table itself has no usage frequency). Rare readings with no
    # supporting words are dropped so the notes stay readable. When no word
    # evidence exists (e.g. rare kanji with irregular words), falls back to
    # the first bank readings.
    def self.common_readings(kanji, words_sorted)
      readings = deduped_readings(kanji)
      top_words = words_sorted.first(RANK_WORD_LIMIT)
      scored = readings.map.with_index do |r, index|
        norm = match_norm(r.reading)
        best = top_words.filter_map do |w|
          next if w.reading.blank?
          next unless norm.present? && match_norm(w.reading).include?(norm)

          w.frequency_rank || Float::INFINITY
        end.min
        [ best, index, r ]
      end
      matched = scored.select(&:first).sort_by { |(best, index, _)| [ best, index ] }
      picked = matched.first(COMMON_READING_COUNT).map(&:last)
      picked = readings.first(COMMON_READING_COUNT) if picked.empty?
      picked.map { |r| ReadingItem.new(reading: r.reading, kind: r.kind) }
    end

    # Readings differing only in dot/dash placement are the same reading: dots
    # mark okurigana boundaries (おこな.う vs おこ.なう) and dashes mark
    # prefix/suffix use (あ.げる vs -あ.げる). Keep the first bank form.
    def self.deduped_readings(kanji)
      seen = {}
      kanji.readings.select do |r|
        norm = match_norm(r.reading)
        next false if norm.blank?

        seen[[ r.kind, norm ]] ? false : (seen[[ r.kind, norm ]] = true)
      end
    end

    def self.sorted_words(words)
      Array(words).sort_by { |w| w.frequency_rank || Float::INFINITY }
    end

    def self.examples_for_kanji(kanji, words_sorted, exclude_sentence_id:, limit:)
      word_ids = words_sorted.first(10).map(&:id)
      return [] if word_ids.empty?

      scope = Sentence.joins(:sentence_words)
                      .where(sentence_words: { word_id: word_ids })
                      .distinct
                      .limit(20)
      scope = scope.where.not(id: exclude_sentence_id) if exclude_sentence_id
      scope.to_a.sort_by { |s| s.japanese.length }.first(limit).map { |s| example_for(s) }
    end

    def self.examples_for_word(word, limit:)
      Sentence.joins(:sentence_words)
              .where(sentence_words: { word_id: word.id })
              .distinct
              .limit(20)
              .to_a.sort_by { |s| s.japanese.length }
              .first(limit)
              .map { |s| example_for(s) }
    end

    def self.example_for(sentence)
      Example.new(html: furigana_html(sentence), translation: sentence.translation)
    end

    # Full-sentence furigana via the existing renderer with a dummy target that
    # never blanks, so every kanji is annotated. Falls back to plain text.
    def self.furigana_html(sentence)
      dummy = Struct.new(:character).new("\u{10FFFF}")
      Learning::Furigana.new(sentence, dummy).render(sentence.japanese)
    rescue StandardError
      ERB::Util.html_escape(sentence.japanese).to_s
    end

    def self.match_norm(text)
      text.to_s.tr("ァ-ン", "ぁ-ん")
          .delete("ー")
          .gsub(/[．.。・\-]/, "")
          .tr(SMALL_KANA, LARGE_KANA)
          .strip
    end
  end
end
