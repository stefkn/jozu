module Learning
  # Spoken-word knownness tap (improvement #4): "Do you say this word?"
  #
  # The learner is fluent in spoken Japanese, so one explicit tap is worth
  # several quiz answers for modeling. Marks the UserWord row with an explicit
  # mastery value, which immediately feeds LeverageCalculator (priority) and
  # SentenceSelector comprehension scoring. Does not create a Review and does
  # not touch SRS state.
  class WordKnownness
    def self.mark!(user, word:, level:, now: Time.current, config: Learning.config)
      new(config:).mark!(user, word:, level:, now:)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def mark!(user, word:, level:, now: Time.current)
      mastery = @config.word_knownness_levels.fetch(level.to_s) do
        raise ArgumentError, "unknown knownness level: #{level}"
      end

      record = UserWord.find_or_initialize_by(user:, word:)
      record.mastery_score = mastery.to_f.clamp(0.0, 1.0)
      record.first_seen_at ||= now
      record.last_seen_at = now
      record.save!
      record
    end
  end
end
