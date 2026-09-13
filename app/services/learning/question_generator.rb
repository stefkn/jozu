module Learning
  # Builds the three Plan A question formats from a reviewable target (plan §8).
  #
  #   kana_to_kanji     prompt = word reading, options = kanji-form words
  #   sentence_to_kanji prompt = sentence with the target kanji blanked
  #   kanji_to_meaning  prompt = kanji, options = meanings
  class QuestionGenerator
    BLANK = "＿＿"

    def self.generate(user, reviewable, question_type:, token: SecureRandom.uuid, now: Time.current)
      new(now:).generate(user, reviewable, question_type:, token:)
    end

    def initialize(now: Time.current)
      @now = now
    end

    def generate(user, reviewable, question_type:, token: SecureRandom.uuid)
      case question_type
      when "kana_to_kanji" then generate_kana_to_kanji(user, reviewable, token)
      when "sentence_to_kanji" then generate_sentence_to_kanji(user, reviewable, token)
      when "kanji_to_meaning" then generate_kanji_to_meaning(reviewable, token)
      else raise ArgumentError, "unknown question type: #{question_type}"
      end
    end

    private

    def generate_kana_to_kanji(user, reviewable, token)
      kanji = reviewable.kanji
      word = best_word_for(kanji, user)
      return nil if word.nil?

      distractors = DistractorSelector.select_for(
        question_type: "kana_to_kanji", target: word, exclude_ids: [ word.id ]
      )
      options = { word.id.to_s => word.surface }
      distractors.each { |id, label| options[id.to_s] = label }

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kana_to_kanji", prompt: word.reading, options:,
                   correct_option_id: word.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now)
    end

    def generate_sentence_to_kanji(user, reviewable, token)
      kanji = reviewable.kanji
      sentence = SentenceSelector.select(user, kanji:)
      return nil if sentence.nil?

      word = target_word_in(sentence, kanji)
      return nil if word.nil?

      prompt = blank_kanji_in(sentence, word, kanji)
      distractors = DistractorSelector.select_for(
        question_type: "sentence_to_kanji", target: kanji, exclude_ids: [ kanji.id ]
      )
      options = { kanji.id.to_s => kanji.character }
      distractors.each { |id, label| options[id.to_s] = label }

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "sentence_to_kanji", prompt:, options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: sentence.id, presented_at: @now)
    end

    def generate_kanji_to_meaning(reviewable, token)
      kanji = reviewable.kanji
      distractors = DistractorSelector.select_for(
        question_type: "kanji_to_meaning", target: kanji, exclude_ids: [ kanji.id ]
      )
      options = { kanji.id.to_s => kanji.meaning_summary }
      distractors.each { |id, label| options[id.to_s] = label }

      Question.new(token:, reviewable_type: reviewable.class.name, reviewable_id: reviewable.id,
                   question_type: "kanji_to_meaning", prompt: kanji.character, options:,
                   correct_option_id: kanji.id.to_s,
                   distractors: distractors.map { |id, _| id }, sentence_id: nil, presented_at: @now)
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

    # Blank the target kanji inside the matched word (決める -> ＿＿めます).
    def blank_kanji_in(sentence, word, kanji)
      sw = sentence.sentence_words.find { |s| s.word_id == word.id }
      if sw&.start_position
        chars = sentence.japanese.chars
        (sw.start_position..sw.end_position).each do |pos|
          chars[pos] = BLANK if chars[pos] == kanji.character
        end
        chars.join
      else
        start = sentence.japanese.index(word.surface)
        return sentence.japanese unless start

        chars = sentence.japanese.chars
        (start...start + word.surface.length).each do |pos|
          chars[pos] = BLANK if chars[pos] == kanji.character
        end
        chars.join
      end
    end
  end
end
