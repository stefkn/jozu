module Learning
  # Tunable constants for the learning algorithms. All values are configurable
  # so tuning never touches the services that read them.
  class Config
attr_accessor :slow_ms, :sentence_slow_ms, :fast_ms, :mastery_deltas,
              :frequency_prior_decay, :priority_weights, :new_kanji_per_session,
              :session_review_target, :known_threshold, :recent_exposure_window,
              :diagnostic_bands, :diagnostic_question_count, :confusion_min_count,
              :confusion_contrast_threshold, :graduation_min_interval,
              :leech_min_reviews, :leech_min_failure_rate, :leech_limit,
              :forecast_days, :acquisition_burst_size, :acquisition_burst_types

    def initialize
      @slow_ms = 4_000
      # Reading a full sentence is inherently slower than picking a single kanji,
      # so sentence questions get a much more generous slow threshold.
      @sentence_slow_ms = 15_000
      @fast_ms = 1_500
      @mastery_deltas = {
        %w[instant knew] => { correct: +0.14, wrong: -0.20 },
        %w[thought] => { correct: +0.09, wrong: -0.22 },
        %w[guessed] => { correct: +0.05, wrong: -0.25 },
        %w[unknown] => { correct: +0.03, wrong: -0.30 }
      }
      @frequency_prior_decay = 0.5
      @priority_weights = { frequency: 1.0, leverage: 1.0, uncertainty: 1.0 }
      @new_kanji_per_session = 3
      @session_review_target = 10
      @known_threshold = 0.6
      @recent_exposure_window = 48.hours
      @diagnostic_bands = [ [ 0, 40 ], [ 40, 80 ], [ 80, nil ] ]
      @diagnostic_question_count = 40
      # A (correct, chosen) pair needs this many wrong answers before it counts
      # as a genuine confusion and gets preferred as a distractor.
      @confusion_min_count = 1
      # ... and this many before a due review becomes a focused 2-option
      # contrast drill (correct vs. the specific confuser).
      @confusion_contrast_threshold = 2
      # An item graduates out of the due queue once it is well-known (mastery
      # at or above known_threshold) and stable (FSRS interval at or beyond
      # this). Graduation is automatic; the learner can resume reviews manually.
      @graduation_min_interval = 30.days
      # Leech definition: at least this many reviews with at least this failure
      # rate, shown capped at leech_limit, worst first.
      @leech_min_reviews = 5
      @leech_min_failure_rate = 0.4
      @leech_limit = 10
      # How many days (including today) the home-screen due forecast covers.
      @forecast_days = 7
      # New-kanji acquisition burst: after the initial kanji_to_meaning question,
      # the same kanji is served again for these follow-up types while times_seen
      # is below the burst size (times_seen 1 -> kana_to_kanji, 2 -> sentence).
      @acquisition_burst_size = 3
      @acquisition_burst_types = { 1 => "kana_to_kanji", 2 => "sentence_to_kanji" }
    end

def slow?(response_time_ms, question_type: nil)
  return false if response_time_ms.nil?

  threshold = question_type == "sentence_to_kanji" ? sentence_slow_ms : slow_ms
  response_time_ms > threshold
  end

    def fast?(response_time_ms)
      response_time_ms && response_time_ms < fast_ms
    end
  end
end
