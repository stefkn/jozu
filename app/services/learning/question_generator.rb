module Learning
  # Builds the three Plan A question formats from a reviewable target (plan §8).
  #
  #   kana_to_kanji     prompt = word reading, options = kanji-form words
  #   sentence_to_kanji prompt = sentence with the target kanji blanked
  #   kanji_to_meaning  prompt = kanji, options = meanings
  class QuestionGenerator
    BLANK = "＿"
    # Below this many options a multiple-choice question is pointless (the
    # learner can only pick the correct answer); the generator returns nil and
    # NextReview falls back to another question type or reviewable.
    MIN_OPTIONS = 2

    def self.generate(user, reviewable, question_type:, token: SecureRandom.uuid, now: Time.current,
                      random: Random.new)
      new(now:, random:).generate(user, reviewable, question_type:, token:)
    end

    def initialize(now: Time.current, random: Random.new)
      @now = now
      @random = random
    end

    def generate(user, reviewable, question_type:, token: SecureRandom.uuid)
      case question_type
      when "kana_to_kanji" then generate_kana_to_kanji(user, reviewable, token)
      when "sentence_to_kanji" then generate_sentence_to_kanji(user, reviewable, token)
      when "kanji_to_meaning" then generate_kanji_to_meaning(user, reviewable, token)
      else raise ArgumentError, "unknown question type: #{question_type}"
      end
    end

    private

    def generate_kana_to_kanji(user, reviewable, token)
      word = reviewable.is_a?(UserWord) ? reviewable.word : best_word_for(kanji_for(reviewable), user)
      return nil if word.nil?

      distractors = DistractorSelector.select_for(
        question_type: "kana_to_kanji", target: word, exclude_ids: [ word.id ]
      )
      options = build_options(word.id, word.surface, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kana_to_kanji", prompt: word.reading, options:,
                   correct_option_id: word.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now)
    end

    def generate_sentence_to_kanji(user, reviewable, token)
      kanji = kanji_for(reviewable)
      return nil if kanji.nil?

      sentence = SentenceSelector.select(user, kanji:)
      return nil if sentence.nil?

      word = target_word_in(sentence, kanji)
      return nil if word.nil?

      prompt = blank_kanji_in(sentence, word, kanji)
      prompt_html = Learning::Furigana.new(sentence, kanji).render(prompt)
      distractors = DistractorSelector.select_for(
        question_type: "sentence_to_kanji", target: kanji, exclude_ids: [ kanji.id ]
      )
      options = build_options(kanji.id, kanji.character, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "sentence_to_kanji", prompt:, prompt_html:, options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: sentence.id, presented_at: @now,
                   translation: sentence.translation)
    end

    def generate_kanji_to_meaning(user, reviewable, token)
      kanji = kanji_for(reviewable)
      return nil if kanji.nil?

      distractors = DistractorSelector.select_for(
        question_type: "kanji_to_meaning", target: kanji, exclude_ids: [ kanji.id ]
      )
      options = build_options(kanji.id, kanji.meaning_summary, distractors)
      return nil if options.nil?

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kanji_to_meaning", prompt: kanji.character,
                   prompt_html: kanji_prompt_html(kanji, user), options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now)
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
