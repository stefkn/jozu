module Learning
  # Records a completed reading passage (improvement #6, concept §13/§20).
  #
  # For each sentence: one kind="reading" exposure per kanji (feeds novelty
  # dedupe) plus a lightweight context_strength bump on tracked UserKanji rows.
  # SRS state and due dates are intentionally untouched — reading reinforces,
  # explicit reviews schedule.
  class ReadingFeedback
    def self.record!(user:, sentences:, now: Time.current, config: Learning.config)
      new(config:).record!(user:, sentences:, now:)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    def record!(user:, sentences:, now: Time.current)
      bump = @config.reading_context_bump.to_f
      Array(sentences).each do |sentence|
        kanji_chars(sentence).each do |char|
          kanji = Kanji.find_by(character: char)
          next if kanji.nil?

          ExposureRecorder.record!(user:, kanji:, sentence_id: sentence.id, kind: "reading", occurred_at: now)
          bump_tracked(user, kanji, bump, now)
        end
      end
    end

    private

    def kanji_chars(sentence)
      sentence.japanese.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }.uniq
    end

    def bump_tracked(user, kanji, bump, now)
      uk = UserKanji.find_by(user_id: user.id, kanji_id: kanji.id)
      return if uk.nil? || uk.graduated_at.present? || uk.suspended_at.present?
      return if bump.zero?

      uk.context_strength = [ [ uk.context_strength + bump, 0.0 ].max, 1.0 ].min
      uk.mastery_score = uk.recompute_mastery
      uk.last_seen_at = now
      uk.save!
    end
  end
end
