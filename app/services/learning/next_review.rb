module Learning
  # Orchestrates "what to show next" (plan §8.1). One deterministic call:
  #
  #   1. Reviews first: earliest due SRS item (user_kanji or user_word).
  #   2. New kanji: highest-priority unseen kanji, capped per session.
  #   3. Question type from the item's weakest dimension, constrained to the
  #      three Plan A types.
  class NextReview
    def self.call(user, now: Time.current, config: Learning.config)
      new(now:, config:).call(user)
    end

    def initialize(now: Time.current, config: Learning.config)
      @now = now
      @config = config
    end

    # @return [Learning::Question, nil] nil when the session is complete.
    def call(user)
      reviewable = next_due(user)
      if reviewable
        generate_for(user, reviewable)
      else
        introduce_new_kanji(user)
      end
    end

    private

    def next_due(user)
      due = user.user_kanji.select { |uk| scheduler.due?(uk, now: @now) }
      due.concat(user.user_words.select { |uw| scheduler.due?(uw, now: @now) })
      due.min_by { |r| [ r.due_at, r.id ] }
    end

    def introduce_new_kanji(user)
      fresh = user.user_kanji.select { |uk| uk.times_seen.zero? && uk.srs_state.blank? }
      introduced_today = user.user_kanji.where(created_at: @now.all_day).count
      return nil if fresh.size >= @config.new_kanji_per_session
      return nil if introduced_today >= @config.new_kanji_per_session

      kanji = PriorityCalculator.new(config: @config).top_unseen(user, limit: 1).first
      return nil if kanji.nil?

      reviewable = UserKanji.create!(user:, kanji:)
      question = QuestionGenerator.new(now: @now).generate(
        user, reviewable, question_type: "kanji_to_meaning"
      )
      return nil if question.nil?

      QuestionStore.put(question)
      question
    end

    def generate_for(user, reviewable)
      question_type = question_type_for(reviewable)
      attempts = [ question_type, fallback_type(question_type) ]
      attempts.each do |type|
        question = QuestionGenerator.new(now: @now).generate(user, reviewable, question_type: type)
        next if question.nil?

        QuestionStore.put(question)
        return question
      end
      nil
    end

    def question_type_for(reviewable)
      return "kana_to_kanji" if reviewable.is_a?(UserWord)
      return "kanji_to_meaning" if reviewable.times_seen.zero?

      if reviewable.context_strength <= reviewable.recognition_strength
        "sentence_to_kanji"
      else
        "kana_to_kanji"
      end
    end

    def fallback_type(type)
      { "sentence_to_kanji" => "kana_to_kanji",
        "kana_to_kanji" => "sentence_to_kanji",
        "kanji_to_meaning" => "kana_to_kanji" }.fetch(type, "kana_to_kanji")
    end

    def scheduler
      @scheduler ||= Scheduler.new(config: @config)
    end
  end
end
