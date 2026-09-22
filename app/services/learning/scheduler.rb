module Learning
  # Thin adapter around the `fsrs` gem. Nothing outside this class touches the
  # gem API (plan §6); swapping the implementation later is internal to here.
  #
  # Card state round-trips through `srs_state` jsonb; `due_at` is denormalised
  # for cheap due-item queries.
  class Scheduler
    RATING_MAP = {
      "again" => Fsrs::Rating::AGAIN,
      "hard" => Fsrs::Rating::HARD,
      "good" => Fsrs::Rating::GOOD,
      "easy" => Fsrs::Rating::EASY
    }.freeze

    Result = Data.define(:grade, :previous_interval, :new_interval, :due_at)

    def self.grade_for(correct:, confidence:, response_time_ms:, question_type: nil, config: Learning.config)
      new(config:).grade_for(correct:, confidence:, response_time_ms:, question_type:)
    end

    def initialize(config: Learning.config)
      @config = config
      @fsrs = Fsrs::Scheduler.new
    end

    # Map the raw outcome + confidence + response time to an FSRS rating (plan §6).
    # The slow threshold is question-type-aware: sentence questions need the time
    # to read the sentence, so they are not penalised at the single-kanji threshold.
    def grade_for(correct:, confidence:, response_time_ms:, question_type: nil)
      return :again if !correct || confidence == "unknown"
      return :hard if confidence == "guessed" || @config.slow?(response_time_ms, question_type:)
      return :easy if confidence == "instant" && @config.fast?(response_time_ms)

      :good
    end

    # Persist a review outcome: rebuild the Fsrs::Card from jsonb, schedule the
    # next interval, and store card + due_at back on the record.
    def apply!(reviewable, grade:, now:)
      card = card_from(reviewable.srs_state)
      rating = RATING_MAP.fetch(grade.to_s)
      scheduling = @fsrs.repeat(card, now)

      next_card = scheduling[rating].card
      previous_interval = card_to_interval(card, now)
      new_interval = next_card.due - now

      reviewable.srs_state = next_card.to_h.as_json
      reviewable.due_at = next_card.due
      reviewable.save!

      Result.new(grade: grade.to_s, previous_interval:, new_interval: new_interval.to_f,
                due_at: next_card.due)
    end

    # A brand-new item: NEW card due immediately. Persists srs_state + due_at.
    def introduce!(reviewable, now:)
      card = Fsrs::Card.new
      reviewable.srs_state = card.to_h.as_json
      reviewable.due_at = now
      reviewable.save!
    end

    # True when the record holds an SRS card that is due for review.
    def due?(reviewable, now:)
      return false unless reviewable.srs_state.present?
      return false unless %w[learning relearning review].include?(state_name(reviewable))

      reviewable.due_at && reviewable.due_at <= now
    end

    def state_name(reviewable)
      state = reviewable.srs_state&.dig("state")
      Fsrs::State.constants.find { |c| Fsrs::State.const_get(c) == state }&.downcase&.to_s
    end

    private

    def card_from(state)
      state.blank? ? Fsrs::Card.new : Fsrs::Card.from_h(state)
    end

    def card_to_interval(card, now)
      card.last_review ? (card.due - card.last_review).to_f : 0.0
    end
  end
end
