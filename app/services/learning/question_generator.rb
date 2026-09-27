module Learning
  # Builds the multiple-choice question formats from a reviewable target (plan §8).
  #
  #   kana_to_kanji     prompt = word reading, options = kanji-form words
  #   kanji_to_reading  prompt = word surface, options = kana readings
  #   sentence_to_kanji prompt = sentence with the target kanji blanked
  #   kanji_to_meaning  prompt = kanji, options = meanings
  #
  # With `contrast:` (default), a target whose top confusion pair has spiked
  # past the contrast threshold is served as a focused 2-option drill (correct
  # vs. the specific confuser) instead of the default 4-option question. Drills
  # keep the base question_type; `Question#drill?` marks them for the UI.
  class QuestionGenerator
    BLANK = "＿"
    DEFAULT_DISTRACTOR_COUNT = 3
    DRILL_DISTRACTOR_COUNT = 1
    # Below this many options a multiple-choice question is pointless (the
    # learner can only pick the correct answer); the generator returns nil and
    # NextReview falls back to another question type or reviewable.
    MIN_OPTIONS = 2

    def self.generate(user, reviewable, question_type:, token: SecureRandom.uuid, now: Time.current,
                      random: Random.new, contrast: true)
      new(now:, random:).generate(user, reviewable, question_type:, token:, contrast:)
    end

    def initialize(now: Time.current, random: Random.new)
      @now = now
      @random = random
    end

    def generate(user, reviewable, question_type:, token: SecureRandom.uuid, contrast: true)
      case question_type
      when "kana_to_kanji" then generate_kana_to_kanji(user, reviewable, token, contrast)
      when "kanji_to_reading" then generate_kanji_to_reading(user, reviewable, token, contrast)
      when "sentence_to_kanji" then generate_sentence_to_kanji(user, reviewable, token, contrast)
      when "kanji_to_meaning" then generate_kanji_to_meaning(user, reviewable, token, contrast)
      else raise ArgumentError, "unknown question type: #{question_type}"
      end
    end

    private

    # A 2-option drill when the target's confusion has spiked, else the default
    # 4-option question. Returns [distractor_count, drill?].
    def drill_format(user, question_type, target_id, contrast)
      if contrast && Learning::ConfusionPairs.spike_for(user, question_type:, target_id:).present?
        [ DRILL_DISTRACTOR_COUNT, true ]
      else
        [ DEFAULT_DISTRACTOR_COUNT, false ]
      end
    end

    def generate_kana_to_kanji(user, reviewable, token, contrast)
      word = reviewable.is_a?(UserWord) ? reviewable.word : best_word_for(kanji_for(reviewable), user)
      return nil if word.nil?

      count, drill = drill_format(user, "kana_to_kanji", word.id, contrast)
      distractors = DistractorSelector.select_for(
        question_type: "kana_to_kanji", target: word, exclude_ids: [ word.id ], count:, user:
      )
      options = build_options(word.id, word.surface, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kana_to_kanji", prompt: word.reading, options:,
                   correct_option_id: word.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now,
                   drill:)
    end

    # Mirror image of kana_to_kanji: the spoken form is known, the learner picks
    # how the word they see is read. Options are confusable words labelled by
    # reading (same-reading words excluded by the pool, so no duplicate labels).
    def generate_kanji_to_reading(user, reviewable, token, contrast)
      word = reviewable.is_a?(UserWord) ? reviewable.word : best_word_for(kanji_for(reviewable), user)
      return nil if word.nil? || word.reading.blank?

      count, drill = drill_format(user, "kanji_to_reading", word.id, contrast)
      distractors = DistractorSelector.select_for(
        question_type: "kanji_to_reading", target: word, exclude_ids: [ word.id ], count:, user:
      )
      options = build_options(word.id, word.reading, distractors)
      return nil if options.nil? || options.values.uniq.size != options.size

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kanji_to_reading", prompt: word.surface, options:,
                   correct_option_id: word.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now,
                   drill:)
    end

    def generate_sentence_to_kanji(user, reviewable, token, contrast)
      kanji = kanji_for(reviewable)
      return nil if kanji.nil?

      sentence = SentenceSelector.select(user, kanji:)
      return nil if sentence.nil?

      word = target_word_in(sentence, kanji)
      return nil if word.nil?

      prompt = blank_kanji_in(sentence, word, kanji)
      prompt_html = Learning::Furigana.new(sentence, kanji).render(prompt)
      count, drill = drill_format(user, "sentence_to_kanji", kanji.id, contrast)
      distractors = DistractorSelector.select_for(
        question_type: "sentence_to_kanji", target: kanji, exclude_ids: [ kanji.id ], count:, user:
      )
      options = build_options(kanji.id, kanji.character, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "sentence_to_kanji", prompt:, prompt_html:, options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: sentence.id, presented_at: @now,
                   translation: sentence.translation, drill:)
    end

    def generate_kanji_to_meaning(user, reviewable, token, contrast)
      kanji = kanji_for(reviewable)
      return nil if kanji.nil?

      count, drill = drill_format(user, "kanji_to_meaning", kanji.id, contrast)
      distractors = DistractorSelector.select_for(
        question_type: "kanji_to_meaning", target: kanji, exclude_ids: [ kanji.id ], count:, user:
      )
      options = build_options(kanji.id, kanji.meaning_summary, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kanji_to_meaning", prompt: kanji.character,
                   prompt_html: kanji_prompt_html(kanji, user), options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now,
                   drill:)
    end

    # The bare target kanji becomes a tappable span so its reading is revealed on
    # tap. The meaning is intentionally NOT included: the question asks the
    # learner to pick the meaning, so showing it would give away the answer.
    def kanji_prompt_html(kanji, user)
      reading = target_reading(kanji, user)
      return nil if reading.blank?

      "<span class=\"kanji-tap\" data-reading=\"#{escape(reading)}\">#{escape(kanji.character)}</span>".html_safe
    end

    # Reading to reveal for a bare target kanji: the most frequent word
    # containing it ties the reading to real vocabulary (決 -> きめる); kanji with
    # no linked word fall back to their primary reading.
    def target_reading(kanji, user)
      best_word_for(kanji, user)&.reading.presence || Learning::Furigana.primary_reading(kanji)
    end

    def escape(text)
      ERB::Util.html_escape(text.to_s)
    end

    # Shuffle options so the correct answer is not always first (Ruby hashes keep
    # insertion order, and the correct option is built first). Answer verification
    # is id-based (correct_option_id), so order is presentation-only. Returns nil
    # when the plausible pool is too thin for a non-degenerate question.
    def build_options(correct_id, correct_label, distractors)
      options = { correct_id.to_s => correct_label }
      distractors.each { |id, label| options[id.to_s] = label }
      options = options.to_a.shuffle(random: @random).to_h
      return nil if options.size < MIN_OPTIONS

      options
    end

    # The kanji under test for either reviewable shape (user_kanji -> kanji,
    # user_word -> the word's first kanji).
    def kanji_for(reviewable)
      return reviewable.kanji if reviewable.respond_to?(:kanji)

      reviewable.respond_to?(:word) ? reviewable.word.kanji.first : nil
    end

    def best_word_for(kanji, user)
      words = kanji.words
      return nil if words.empty?

      known_ids = UserWord.where(user_id: user.id, word_id: words.map(&:id)).pluck(:word_id)
      pool = known_ids.empty? ? words : words.select { |w| known_ids.include?(w.id) }
      pool.min_by { |w| w.frequency_rank || Float::INFINITY }
    end

    def target_word_in(sentence, kanji)
      kanji_words = kanji.words.map(&:id)
      sentence.sentence_words.map(&:word).find { |w| kanji_words.include?(w.id) }
    end

    # Blank every occurrence of the target kanji so a single-kanji answer never
    # leaks into the prompt (決める -> ＿めます; every 日 in 日曜日/日本語 -> ＿).
    def blank_kanji_in(sentence, _word, kanji)
      sentence.japanese.gsub(kanji.character, BLANK)
    end
  end
end
