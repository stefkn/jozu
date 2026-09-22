module Generation
  # Shared retry + JSON-extraction helpers for LLM calls (plan §4.2/§4.3).
  # OpenRouter providers are flaky (429/5xx) and many models wrap JSON in
  # markdown fences, so every call site funnels through here.
  module Response
    MAX_RETRIES = 4
    RETRY_BACKOFF_SECONDS = 2.0
    JSON_FENCE = /\A```(?:json)?\s*(.*?)\s*```\z/im
    # Only transient failures are retried; a 4xx (bad request/auth) is fatal.
    RETRYABLE_ERRORS = [
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      Faraday::ServerError,
      Faraday::TooManyRequestsError
    ].freeze

    def with_retries(logger:, max_retries: MAX_RETRIES)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue *RETRYABLE_ERRORS => e
        raise if attempts > max_retries

        logger.warn "Request failed (attempt #{attempts}/#{max_retries}): #{e.class} #{e.message}"
        sleep(RETRY_BACKOFF_SECONDS * attempts)
        retry
      end
    end

    # Extracts the first balanced JSON object from a model reply, tolerating
    # markdown fences and prose around the payload. Returns a Hash or nil.
    def parse_json_response(content, logger:)
      return nil if content.nil?

      text = content.strip.sub(JSON_FENCE, '\1')
      start_idx = text.index("{")
      end_idx = text.rindex("}")
      return nil unless start_idx && end_idx && end_idx > start_idx

      JSON.parse(text[start_idx..end_idx])
    rescue JSON::ParserError => e
      logger.warn "Unparseable model response: #{e.message}"
      nil
    end
  end
end
