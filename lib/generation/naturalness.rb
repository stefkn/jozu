module Generation
  # Naturalness rating gate (plan §4.3, gate 4). A cheap LLM call scores a
  # generated sentence 1–5; scores below KEEP_SCORE are dropped at import.
  # Unparseable rows get one retry at a higher temperature, then fail closed.
  class Naturalness
    include Response

    PROMPT_VERSION = "v1"
    KEEP_SCORE = 3
    MAX_ATTEMPTS = 2
    RETRY_TEMPERATURE = 1.0

    # @param model [String] OpenRouter model slug. Defaults to JOZU_NATURALNESS_MODEL
    #   so the (cheap, tiny-output) rating pass can use a stronger model than
    #   generation without affecting generation's model.
    def initialize(model: ENV["JOZU_NATURALNESS_MODEL"].presence || ENV.fetch("JOZU_LLM_MODEL", "anthropic/claude-sonnet-4"),
                   keep_score: KEEP_SCORE, max_tokens: 50, openai: nil, logger: Logger.new($stdout))
      @model = model
      @keep_score = keep_score
      @max_tokens = max_tokens
      @openai = openai
      @logger = logger
    end

    # @return [Boolean] true when the sentence is natural enough to keep.
    def keep?(sentence)
      score = rate(sentence)
      !score.nil? && score >= @keep_score
    end

    # @return [Integer, nil] 1–5, or nil when no usable score was produced.
    def rate(sentence)
      MAX_ATTEMPTS.times do |attempt|
        temperature = attempt.zero? ? 0.0 : RETRY_TEMPERATURE
        params = {
          model: @model,
          temperature:,
          max_tokens: @max_tokens,
          messages: [ { role: "user", content: prompt(sentence) } ]
        }
        response = with_retries(logger: @logger) { client.chat(parameters: params) }
        body = parse_json_response(response.dig("choices", 0, "message", "content"), logger: @logger)
        score = body && body["score"]
        return score.to_i if score.is_a?(Numeric)

        @logger.warn "Unparseable naturalness score for #{sentence[0, 20]}..."
      end
      nil
    end

    private

    def client
      @client ||= @openai || Generation::Client.build
    end

    def prompt(sentence)
      <<~PROMPT
        Rate the naturalness of this Japanese sentence on a scale of 1 to 5:
        - 1–2: awkward, unnatural, or grammatically wrong
        - 3: an ordinary, grammatically correct everyday sentence
        - 4–5: perfectly natural native Japanese
        Sentence: #{sentence}
        Return strict JSON: {"score": <integer 1-5>}
      PROMPT
    end
  end
end
