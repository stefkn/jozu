module Learning
  # New-kanji acquisition burst (improvement #1).
  #
  # A freshly introduced kanji gets varied back-to-back encounters in its first
  # session instead of a single kanji_to_meaning question:
  #   times_seen 0 -> kanji_to_meaning (handled by NextReview's fresh path)
  #   times_seen 1 -> kana_to_kanji (word form)
  #   times_seen 2 -> sentence_to_kanji (context)
  #
  # Detection is via times_seen so no migration is needed. Burst items are
  # served ahead of the normal due queue to keep encoding contiguous; each
  # answer still flows through MasteryCalculator + Scheduler normally.
  class AcquisitionBurst
    def self.pending(user, config: Learning.config)
      new(config:).pending(user)
    end

    def self.burst_type(times_seen, config: Learning.config)
      new(config:).burst_type(times_seen)
    end

    def initialize(config: Learning.config)
      @config = config
    end

    # UserKanji rows with times_seen in 1...burst_size that still need a
    # follow-up, oldest first. Graduated/suspended/skipped items are out.
    def pending(user)
      size = @config.acquisition_burst_size.to_i
      return [] if size <= 1

      rows = UserKanji.where(user_id: user.id)
                      .where("times_seen >= 1 AND times_seen < ?", size)
                      .where(graduated_at: nil, suspended_at: nil)
                      .includes(:kanji)
                      .to_a
      rows.reject { |uk| NumberFilter.skip?(user, uk) }
          .sort_by { |uk| [ uk.last_seen_at || uk.updated_at, uk.id ] }
    end

    # Preferred follow-up type for the burst step, or nil when the item has
    # completed its burst.
    def burst_type(times_seen)
      @config.acquisition_burst_types[times_seen]
    end
  end
end
