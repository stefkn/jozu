module Learning
  # Records a contextual exposure (plan §3.3). In Plan A this dedupes sentence
  # selection: "has this sentence been shown for this kanji recently?" The table
  # is reused by Plan B for passive-weighting and reading-stream tracking.
  class ExposureRecorder
    def self.record!(user:, kanji:, sentence: nil, sentence_id: nil, kind: "sentence", occurred_at: Time.current)
      Exposure.create!(user:, kanji:, sentence_id: sentence&.id || sentence_id, kind:, occurred_at:)
    end

    def self.recently_seen?(user, kanji, sentence, within: Learning.config.recent_exposure_window)
      Exposure.exists?(user:, kanji:, sentence:, kind: "sentence",
                       occurred_at: within.ago..Time.current)
    end

    def self.seen_count(user, kanji, sentence)
      Exposure.where(user:, kanji:, sentence:).count
    end
  end
end
