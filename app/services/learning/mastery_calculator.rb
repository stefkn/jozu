module Learning
  # Updates the per-dimension strengths on a review (concept §3, plan §5).
  #
  # The confidence bucket selects the delta; correctness decides sign. The result
  # is clamped to [0, 1]. UserKanji/user_word counters are updated independently.
  #
  # Question types update exactly one dimension (plan §5.1):
  #   kana_to_kanji / kanji_to_meaning  -> recognition_strength
  #   sentence_to_kanji                 -> context_strength
  class MasteryCalculator
    Result = Data.define(:previous_mastery, :new_mastery)

    QUESTION_DIMENSIONS = {
      "kana_to_kanji" => :recognition_strength,
      "kanji_to_meaning" => :recognition_strength,
      "sentence_to_kanji" => :context_strength
    }.freeze

    def self.update!(reviewable, question_type:, correct:, confidence:, now: Time.current)
      new(config: Learning.config).update!(reviewable, question_type:, correct:, confidence:, now:)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def update!(reviewable, question_type:, correct:, confidence:, now: Time.current)
      delta = delta_for(confidence, correct:)
      previous = reviewable.mastery_score

      update_dimension(reviewable, question_type, delta, now:)
      update_counters(reviewable, correct, now:)
      reviewable.save!

      Result.new(previous_mastery: previous, new_mastery: reviewable.mastery_score)
    end

    private

    def update_dimension(reviewable, question_type, delta, now:)
      case reviewable
      when UserKanji
        dimension = QUESTION_DIMENSIONS.fetch(question_type, :recognition_strength)
        reviewable.public_send("#{dimension}=", clamp01(reviewable.public_send(dimension) + delta))
        reviewable.mastery_score = reviewable.recompute_mastery
      else
        reviewable.mastery_score = clamp01(reviewable.mastery_score + delta)
      end
    end

    def update_counters(reviewable, correct, now:)
      reviewable.times_seen += 1
      correct ? reviewable.times_correct += 1 : reviewable.times_incorrect += 1
      reviewable.first_seen_at ||= now
      reviewable.last_seen_at = now
    end

    def delta_for(confidence, correct:)
      bucket = @config.mastery_deltas.keys.find { |k| k.include?(confidence.to_s) }
      bucket ||= @config.mastery_deltas.keys.first
      @config.mastery_deltas[bucket][correct ? :correct : :wrong]
    end

    def clamp01(value)
      [ [ value, 0.0 ].max, 1.0 ].min
    end
  end
end
