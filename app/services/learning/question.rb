module Learning
  # Immutable question payload handed to the quiz UI and stored (keyed by token)
  # so POST /reviews can verify the answer without trusting the client.
  Question = Data.define(:token, :reviewable_type, :reviewable_id, :question_type,
                         :prompt, :options, :correct_option_id, :distractors, :sentence_id,
                         :presented_at, :prompt_html, :translation) do
    def initialize(token:, reviewable_type:, reviewable_id:, question_type:, prompt:, options:,
                   correct_option_id:, distractors:, sentence_id:, presented_at:, prompt_html: nil,
                   translation: nil)
      super
    end

    def correct?(answer_id)
      answer_id.to_s == correct_option_id.to_s
    end
  end
end
