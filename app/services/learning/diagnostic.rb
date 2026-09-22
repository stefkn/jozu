module Learning
  # Rapid onboarding diagnostic (concept §23, plan §9). The learner answers a
  # capped set of kana-to-kanji questions sampled adaptively across frequency
  # bands; wrong answers push toward easier bands, correct answers push harder.
  #
  # Answers are recorded as reviews and batch-seed user_kanji / user_words so the
  # priority engine starts from a sensible estimate instead of a blank slate.
  class Diagnostic
    State = Data.define(:band, :asked, :total, :answers, :used_ids) do
      def finished?
        asked >= total
      end
    end

    Answer = Data.define(:word_id, :correct)

    def self.state_key(user)
      "jozu:diagnostic:#{user.id}"
    end

    def self.state_for(user, config: Learning.config)
      Rails.cache.fetch(state_key(user)) { new_state(config) }
    end

    def self.new_state(config)
      State.new(band: 1, asked: 0, total: config.diagnostic_question_count, answers: [], used_ids: [])
    end

    def self.start(user, now: Time.current, config: Learning.config)
      new(now:, config:).start(user)
    end

    def self.answer(user, word_id:, correct:, confidence:, now: Time.current, config: Learning.config)
      new(now:, config:).answer(user, word_id:, correct:, confidence:)
    end

    def self.finish!(user, now: Time.current, config: Learning.config)
      new(now:, config:).finish!(user)
    end

    def initialize(now: Time.current, config: Learning.config)
      @now = now
      @config = config
    end

def start(user)
      state = self.class.state_for(user, config: @config)
      return nil if state.finished?

      question_for(user, state)
    end

    # Records the answer, adjusts the band, and returns the next question — or
    # nil when the diagnostic is complete.
    def answer(user, word_id:, correct:, confidence:)
      state = self.class.state_for(user, config: @config)
      return nil if state.finished?

      state = State.new(
        band: next_band(state.band, correct),
        asked: state.asked + 1,
        total: state.total,
        answers: state.answers + [ Answer.new(word_id:, correct:) ],
        used_ids: state.used_ids + [ word_id ]
      )
      Rails.cache.write(self.class.state_key(user), state)
      self.class.finish!(user, now: @now, config: @config) if state.finished?
      state.finished? ? nil : question_for(user, state)
    end

    def finish!(user)
      state = self.class.state_for(user, config: @config)
      Rails.cache.delete(self.class.state_key(user))
      seed!(user, state)
      state
    end

    private

    def question_for(user, state)
      word = next_word(user, state)
      return nil if word.nil?

      flashcard = Flashcard.new(token: SecureRandom.uuid, word_id: word.id,
                                front: word.surface, back: word.reading)
      QuestionStore.put(flashcard)
      flashcard
    end

    def next_word(user, state)
      bands = @config.diagnostic_bands
      lo, hi = bands[state.band.clamp(0, bands.size - 1)]
      pool = if hi
               Word.where("frequency_rank >= ? AND frequency_rank < ?", lo, hi)
      else
               Word.where("frequency_rank >= ?", lo)
      end
      pool = pool.where.not(id: state.used_ids)
      pool = Word.where.not(id: state.used_ids) if pool.empty?
      pool = exclude_number_words(pool) if user.skip_number_kanji?
      pool.order("random()").limit(1).first
    end

    # Users who opt out of number kanji are never tested on words that contain one.
    def exclude_number_words(pool)
      number_kanji_ids = Kanji.where(character: Kanji::NUMBER_KANJI).pluck(:id)
      pool.where.not(id: WordKanji.where(kanji_id: number_kanji_ids).select(:word_id))
    end

    def next_band(band, correct)
      return 0 if correct == false && band.zero?
      return band + 1 if correct && band < @config.diagnostic_bands.size - 1
      return band - 1 if correct == false && band.positive?

      band
    end

    # Batch-seed user_kanji / user_words and record diagnostic reviews (plan §9).
    def seed!(user, state)
      state.answers.each do |answer|
        word = Word.find_by(id: answer.word_id)
        next if word.nil?

        record_word(user, word, answer.correct)
      end
    end

    def record_word(user, word, correct)
      confidence = "knew"
      if correct
        user_word = UserWord.find_or_initialize_by(user:, word:)
        user_word.mastery_score = 0.6
        user_word.save!
      end

      word.word_kanji.map(&:kanji).uniq.each do |kanji|
        user_kanji = UserKanji.find_or_initialize_by(user:, kanji:)
        user_kanji.recognition_strength = correct ? 0.75 : 0.20
        user_kanji.mastery_score = user_kanji.recompute_mastery
        user_kanji.times_seen += 1
        user_kanji.save!
        Scheduler.new(config: @config).introduce!(user_kanji, now: @now)

        reviewable = correct ? (UserWord.find_by(user:, word:) || user_kanji) : user_kanji
        Review.create!(
          user:,
          reviewable:,
          question_type: "kanji_recognition",
          grade: correct ? "good" : "again",
          distractors: [],
          presented_at: @now,
          answered_at: @now,
          correct:,
          confidence:,
          response_time_ms: nil,
          question_token: SecureRandom.uuid
        )
      end
    end
  end
end
