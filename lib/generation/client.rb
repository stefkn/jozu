module Generation
  # OpenAI-compatible client pointed at OpenRouter (plan §4.2). OpenRouter's
  # /v1 API speaks the OpenAI chat protocol, so ruby-openai works unchanged;
  # this factory only sets the base URL and attribution headers. Overridable
  # via env for tests or a different provider (JOZU_LLM_BASE_URL).
  class Client
    DEFAULT_BASE_URL = "https://openrouter.ai/api/v1"
    DEFAULT_REFERER = "http://localhost:3001"
    DEFAULT_TITLE = "Jozu"

    def self.build(access_token: nil, base_url: nil, referer: nil, title: nil)
      access_token ||= ENV["OPENROUTER_API_KEY"] || ENV["OPENAI_API_KEY"]
      if access_token.blank?
        raise "OPENROUTER_API_KEY (or OPENAI_API_KEY) is required for LLM generation"
      end

      OpenAI::Client.new(
        access_token: access_token,
        uri_base: base_url || ENV["JOZU_LLM_BASE_URL"].presence || DEFAULT_BASE_URL,
        extra_headers: {
          "HTTP-Referer" => referer || ENV["JOZU_REFERER"].presence || DEFAULT_REFERER,
          "X-Title" => title || ENV["JOZU_TITLE"].presence || DEFAULT_TITLE
        }
      )
    end
  end
end
