module Learning
  # "How far through today's session am I?" for the quiz progress bar.
  #
  # answered = quiz reviews already banked today; remaining = what a session
  # would still serve right now (due reviews + new-kanji slots, same inputs as
  # NextReview). The bar fills against whichever is smaller — the daily target
  # or the actual work — so it always reaches 100% when the session ends,
  # whether it ends on the target or on an empty queue. Past the target
  # (practice mode), it pins at 100% while the count keeps climbing.
  class SessionProgress
    Result = Data.define(:answered, :total) do
      def percent
        return 0 if total.zero?

        [ (answered * 100 / total), 100 ].min
      end
    end

    def self.call(user, now: Time.current, config: Learning.config)
      new(now:, config:).call(user)
    end

    def initialize(now: Time.current, config: Learning.config)
      @now = now
      @config = config
    end

    def call(user)
      answered = Review.quiz.where(user:, created_at: @now.all_day).count
      summary = Session.summary(user, now: @now, config: @config)
      remaining = summary.reviews_count + summary.new_kanji_count
      total = [ answered + remaining, @config.session_review_target ].min
      Result.new(answered:, total: [ total, 1 ].max)
    end
  end
end
