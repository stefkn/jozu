module Learning
  # Today's-session summary for the home screen (plan §10.1).
  class Session
    Summary = Data.define(:reviews_count, :new_kanji_count, :reading_count)

    def self.summary(user, now: Time.current, config: Learning.config)
      new(now:, config:).summary(user)
    end

    def initialize(now: Time.current, config: Learning.config)
      @now = now
      @config = config
    end

    def summary(user)
      Summary.new(
        reviews_count: due_count(user),
        new_kanji_count: new_kanji_count(user),
        reading_count: reading_count(user)
      )
    end

    private

    def due_count(user)
      scheduler = Scheduler.new(config: @config)
      kanji_due = user.user_kanji.select { |uk| scheduler.due?(uk, now: @now) && !NumberFilter.skip?(user, uk) }
      word_due = user.user_words.count { |uw| scheduler.due?(uw, now: @now) && !NumberFilter.skip?(user, uw) }
      due_ids = kanji_due.map(&:id).to_set
      burst_extra = AcquisitionBurst.new(config: @config).pending(user).count { |uk| !due_ids.include?(uk.id) }
      kanji_due.size + word_due + burst_extra
    end

    def new_kanji_count(user)
      fresh = user.user_kanji.count { |uk| uk.times_seen.zero? && uk.srs_state.blank? && !NumberFilter.skip?(user, uk) }
      introduced_today = user.user_kanji.where(created_at: @now.all_day).count
      unseen = user.skip_number_kanji? ? Kanji.where.not(character: Kanji::NUMBER_KANJI).count : Kanji.count
      extra_eligible = unseen - user.user_kanji.count
      if user.practice_mode?
        fresh + extra_eligible
      else
        remaining_slots = [ @config.new_kanji_per_session - introduced_today, 0 ].max
        fresh + [ remaining_slots, extra_eligible ].min
      end
    end

    # 1 when a short reading is available, else 0. Cheap existence check so
    # the home screen stays fast even on a large sentence bank.
    def reading_count(user)
      ReadingPassage.available?(user, config: @config) ? 1 : 0
    rescue StandardError
      0
    end
  end
end
