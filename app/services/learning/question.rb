module Learning
  # Immutable question payload handed to the quiz UI and stored (keyed by token)
  # so POST /reviews can verify the answer without trusting the client.
  Question = Data.define(:token, :reviewable_type, :reviewable_id, :question_type,
                           :prompt, :options, :correct_option_id, :distractors, :sentence_id,
                           :presented_at, :prompt_html, :translation, :drill) do
    def initialize(token:, reviewable_type:, reviewable_id:, question_type:, prompt:, options:,
                   correct_option_id:, distractors:, sentence_id:, presented_at:, prompt_html: nil,
                   translation: nil, drill: false)
      super
    end

    def correct?(answer_id)
      answer_id.to_s == correct_option_id.to_s
    end

    # A drill is a focused 2-option review (correct vs. one spiking confuser).
    # Drills keep the base question_type so mastery, SRS and analytics stay
    # coherent; drill rows are identifiable by a single-entry distractors array.
    def drill?
      !!drill
    end
  end
end
