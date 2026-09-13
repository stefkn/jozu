module Generation
  # Offline batch LLM sentence generation (plan §4.2). Produces a versioned JSONL
  # file at vendor/data/generated_sentences.jsonl; the API is called once and the
  # file is the source of truth for later imports.
  class SentenceGenerator
    PROMPT_VERSION = "v1"
    OUTPUT_PATH = Rails.root.join("vendor/data/generated_sentences.jsonl")

    def initialize(model: ENV.fetch("JOZU_LLM_MODEL", "gpt-4o-mini"), temperature: 0.8,
                   seed: 42, max_other_kanji_rank: 2000, openai: nil, logger: Logger.new($stdout))
      @model = model
      @temperature = temperature
      @seed = seed
      @max_other_kanji_rank = max_other_kanji_rank
      @logger = logger
      @client = openai || build_client
    end

    # @return [Integer] number of generation units appended to the JSONL.
    def run!(limit: nil)
      units = build_units.limit(limit)
      count = 0
      units.each do |unit|
        result = generate_one(unit)
        append(result, unit)
        count += 1
      end
      count
    end

    def build_units(limit: nil)
      scope = Word.joins(:word_kanji).distinct.order(:frequency_rank)
      scope = scope.limit(limit) if limit
      scope.map do |word|
        # one unit per (word × kanji) pair so each kanji gets sentence exposure
        word.kanji.map { |kanji| Unit.new(word:, kanji:, max_other_kanji_rank: @max_other_kanji_rank) }
      end.flatten
    end

    private

    Unit = Struct.new(:word, :kanji, :max_other_kanji_rank, keyword_init: true)

    def build_client
      key = ENV["OPENAI_API_KEY"]
      raise "OPENAI_API_KEY is required for sentence generation" if key.blank?

      OpenAI::Client.new(access_token: key)
    end

    def generate_one(unit)
      prompt = <<~PROMPT
        Write one natural, grammatically correct Japanese sentence that uses the word "#{unit.word.surface}"
        (meaning: "#{unit.word.meaning}") in context.
        Requirements:
        - Must contain the exact word "#{unit.word.surface}".
        - Apart from that word, every kanji must be among the top #{unit.max_other_kanji_rank} most frequent kanji.
        - 6–30 characters, natural everyday Japanese, no filler set-phrases.
        Return strict JSON: {"ja": "...", "en": "..."}
      PROMPT

      response = @client.chat(parameters: {
        model: @model,
        temperature: @temperature,
        seed:,
        response_format: { type: "json_object" },
        messages: [ { role: "user", content: prompt } ]
      })
      content = response.dig("choices", 0, "message", "content")
      JSON.parse(content)
    rescue JSON::ParserError => e
      @logger.warn "Unparseable response for #{unit.word.surface}: #{e.message}"
      nil
    end

    def append(result, unit)
      return if result.nil?

      row = {
        word: unit.word.surface,
        kanji: unit.kanji.character,
        ja: result["ja"],
        en: result["en"],
        model: @model,
        prompt_version: PROMPT_VERSION,
        temperature: @temperature,
        seed:,
        generated_at: Time.current.utc.iso8601
      }
      OUTPUT_PATH.dirname.mkpath
      File.open(OUTPUT_PATH, "a") { |f| f.puts(JSON.generate(row)) }
      @logger.info "Generated sentence for #{unit.word.surface} (#{unit.kanji.character})"
    end
  end
end
