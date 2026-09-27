module Learning
  # "What's coming up?" counts for the home screen: per-day due counts for the
  # next `forecast_days` days (including today; overdue items count as today).
  #
  # Same eligibility as the due queue — Scheduler state, no graduated/suspended
  # items, no skipped number kanji — so the strip always agrees with what a
  # session would actually serve. Future due dates are FSRS predictions: an
  # early/late review reshuffles them, so the UI labels these "expected".
  class Forecast
    Day = Data.define(:date, :count)
    Result = Data.define(:days, :later_count) do
      def total
        days.sum(&:count)
      end
    end

    ELIGIBLE_STATES = %w[learning relearning review].freeze

    def self.call(user, days: nil, now: Time.current, config: Learning.config)
      new(now:, config:).call(user, days: days || config.forecast_days)
    end

    def initialize(now: Time.current, config: Learning.config)
      @now = now
      @config = config
      @scheduler = Scheduler.new(config:)
    end

    def call(user, days:)
      today = @now.to_date
      counts = Array.new(days, 0)
      later = 0

      reviewables(user).each do |record|
        due_at = record.due_at
        next if due_at.nil?

        index = (due_at.to_date - today).to_i
        index = 0 if index.negative?
        if index < days
          counts[index] += 1
        else
          later += 1
        end
      end

      Result.new(
        days: counts.each_with_index.map { |count, i| Day.new(date: today + i, count:) },
        later_count: later
      )
    end

    private

    def reviewables(user)
      kanji = user.user_kanji.includes(:kanji).to_a
      words = user.user_words.includes(word: :kanji).to_a
      (kanji + words).select { |record| countable?(user, record) }
    end

    def countable?(user, record)
      return false if record.graduated_at.present? || record.suspended_at.present?
      return false if record.srs_state.blank? || record.due_at.nil?
      return false unless ELIGIBLE_STATES.include?(@scheduler.state_name(record))
      return false if NumberFilter.skip?(user, record)

      true
    end
  end
end
