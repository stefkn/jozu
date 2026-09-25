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
        generate_for(user)
      else
        introduce_new_kanji(user)
      end
    end

    private

    def next_due(user)
      due_reviewables(user).min_by { |r| [ r.due_at, r.id ] }
    end

    def due_reviewables(user)
      due = user.user_kanji.select { |uk| scheduler.due?(uk, now: @now) }
      due.concat(user.user_words.select { |uw| scheduler.due?(uw, now: @now) })
      due.reject { |r| NumberFilter.skip?(user, r) }
    end

    def introduce_new_kanji(user)
      # Query the DB, not the (possibly stale) cached `user.user_kanji` association:
      # answering a question saves a fresh record that the in-memory cache misses.
      fresh = UserKanji.where(user_id: user.id).select { |uk| uk.times_seen.zero? && uk.srs_state.blank? }
      fresh = fresh.reject { |uk| NumberFilter.skip?(user, uk) }

      # An already-introduced-but-unanswered kanji (an interrupted session) is
      # served first; only introduce a NEW kanji while under the per-session cap.
      # Otherwise a session deadlocks as soon as the fresh pool fills up, showing
      # "session complete" forever.
      unless fresh.empty?
        return generate_question(user, fresh.min_by(&:created_at), "kanji_to_meaning")
      end

      return nil if !user.practice_mode? && user.user_kanji.where(created_at: @now.all_day).count >= @config.new_kanji_per_session

      kanji = PriorityCalculator.new(config: @config).top_unseen(user, limit: 1).first
      return nil if kanji.nil?

      generate_question(user, UserKanji.create!(user:, kanji:), "kanji_to_meaning")
    end

    def generate_question(user, reviewable, question_type)
      question = QuestionGenerator.new(now: @now).generate(user, reviewable, question_type:)
      return nil if question.nil?

      QuestionStore.put(question)
      question
    end

    def generate_for(user)
      # Try each due reviewable in due order; if one can't produce a
      # non-degenerate question (e.g. its distractor pool is empty), move on to
      # the next instead of dead-ending the session. The association order is
      # unspecified, so sort explicitly by due date before iterating.
      due = due_reviewables(user).sort_by { |r| [ r.due_at, r.id ] }
      due.each do |item|
        attempts = [ question_type_for(item), fallback_type(question_type_for(item)) ].uniq
        attempts.each do |type|
          question = QuestionGenerator.new(now: @now).generate(user, item, question_type: type)
          next if question.nil?

          QuestionStore.put(question)
          return question
        end
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
