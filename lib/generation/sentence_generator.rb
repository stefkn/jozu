module Generation
  # Offline batch LLM sentence generation (plan §4.2). Produces a versioned JSONL
  # file at vendor/data/generated_sentences.jsonl; the API is called once and the
  # file is the source of truth for later imports.
  #
  # Resumable: units whose (word × kanji) pair already appears in the output file
  # are skipped, so an interrupted batch is restarted with the same command. The
  # run also retries transient transport / rate-limit errors and extracts JSON
  # from models that wrap it in markdown code fences.
  class SentenceGenerator
    include Response

    PROMPT_VERSION = "v1"
    OUTPUT_PATH = Rails.root.join("vendor/data/generated_sentences.jsonl")

    # @param model [String] OpenRouter model slug.
    # @param max_tokens [Integer] output token cap. OpenRouter reserves the model's
    #   full max output (e.g. 64k for Claude) when unset and rejects the request
    #   if the balance can't cover it; an explicit small cap also bounds cost.
    # @param json_mode [Boolean] send `response_format: json_object`. Off by
    #   default: several OpenRouter providers (e.g. Claude) reject it; the prompt
    #   plus fence-tolerant parsing cover those cases.
    # @param send_seed [Boolean] send the OpenAI `seed` parameter (provider-dependent).
    # @param concurrency [Integer] number of parallel in-flight requests.
    # @param openai [Object, nil] injectable OpenAI-compatible client (tests).
    # @param output_path [Pathname] where rows are appended (tests).
    def initialize(model: ENV.fetch("JOZU_LLM_MODEL", "anthropic/claude-sonnet-4"),
                   temperature: 0.8, seed: 42, max_other_kanji_rank: 2000,
                   max_tokens: 500, json_mode: false, send_seed: false,
                   concurrency: 1, openai: nil, output_path: OUTPUT_PATH, logger: Logger.new($stdout))
      @model = model
      @temperature = temperature
      @seed = seed
      @max_other_kanji_rank = max_other_kanji_rank
      @max_tokens = max_tokens
      @json_mode = json_mode
      @send_seed = send_seed
      @concurrency = [ concurrency.to_i, 1 ].max
      @openai = openai
      @output_path = output_path
      @logger = logger
    end

    # @return [Integer] number of new rows appended to the JSONL.
    def run!(limit: nil)
      existing = load_existing_keys
      units = build_units.reject { |unit| existing.key?(unit_key(unit)) }
      units = units.first(limit) if limit
      @logger.info "Skipping #{existing.size} already-generated (word × kanji) pairs" if existing.any?

      generated = generate_all(units)
      @logger.info "Appended #{generated} rows (#{units.size - generated} failures)."
      generated
    end

    # One unit per (word × kanji) pair, most frequent words first, so each kanji
    # gets sentence exposure and high-leverage words are generated first.
    def build_units
      Word.joins(:word_kanji).distinct.order(:frequency_rank).map do |word|
        word.kanji.map { |kanji| Unit.new(word:, kanji:, max_other_kanji_rank: @max_other_kanji_rank) }
      end.flatten
    end

    private

    Unit = Struct.new(:word, :kanji, :max_other_kanji_rank, keyword_init: true)

    def client
      @client ||= @openai || Generation::Client.build
    end

    def generate_all(units)
      return generate_sequential(units) if @concurrency == 1

      generate_concurrent(units)
    end

    def generate_sequential(units)
      count = 0
      units.each do |unit|
        result = generate_one(unit)
        next unless result

        count += 1 if append(result, unit)
      end
      count
    end

    def generate_concurrent(units)
      queue = Queue.new
      units.each { |unit| queue << unit }

      mutex = Mutex.new
      total = 0
      workers = @concurrency.times.map do
        Thread.new do
          local = 0
          while (unit = pop(queue))
            result = generate_one(unit)
            next unless result

            local += 1 if mutex.synchronize { append(result, unit) }
          end
          mutex.synchronize { total += local }
        end
      end
      workers.each(&:join)
      total
    end

    def pop(queue)
      queue.pop(true)
    rescue ThreadError
      nil
    end

    def generate_one(unit)
      params = {
        model: @model,
        temperature: @temperature,
        max_tokens: @max_tokens,
        messages: [ { role: "user", content: build_prompt(unit) } ]
      }
      params[:seed] = @seed if @send_seed
      params[:response_format] = { type: "json_object" } if @json_mode

      response = with_retries(logger: @logger) { client.chat(parameters: params) }
      log_usage(response)
      parse_json_response(response.dig("choices", 0, "message", "content"), logger: @logger)
    end

    def log_usage(response)
      usage = response.dig("usage")
      return unless usage

      @logger.info "usage: #{usage['prompt_tokens']} prompt / #{usage['completion_tokens']} completion tokens"
    end

    def build_prompt(unit)
      <<~PROMPT
        Write one natural, grammatically correct Japanese sentence that uses the word "#{unit.word.surface}"
        (meaning: "#{unit.word.meaning}") in context.
        Requirements:
        - Must contain the exact word "#{unit.word.surface}".
        - Apart from that word, every kanji must be among the top #{unit.max_other_kanji_rank} most frequent kanji.
        - 6–30 characters, natural everyday Japanese, no filler set-phrases.
        Return strict JSON: {"ja": "...", "en": "..."}
      PROMPT
    end

    def append(result, unit)
      return false if result["ja"].to_s.strip.empty? || result["en"].to_s.strip.empty?

      row = {
        word: unit.word.surface,
        kanji: unit.kanji.character,
        ja: result["ja"],
        en: result["en"],
        model: @model,
        prompt_version: PROMPT_VERSION,
        temperature: @temperature,
        seed: @seed,
        generated_at: Time.current.utc.iso8601
      }
      @output_path.dirname.mkpath
      File.open(@output_path, "a") { |f| f.puts(JSON.generate(row)) }
      @logger.info "Generated sentence for #{unit.word.surface} (#{unit.kanji.character})"
      true
    end

    def load_existing_keys
      return {} unless @output_path.exist?

      File.readlines(@output_path, chomp: true).each_with_object({}) do |line, keys|
        row = JSON.parse(line) rescue next
        keys[unit_key_from_row(row)] = true if row["word"] && row["kanji"]
      end
    end

    def unit_key(unit)
      "#{unit.word.surface}\u0000#{unit.kanji.character}"
    end

    def unit_key_from_row(row)
      "#{row['word']}\u0000#{row['kanji']}"
    end
  end
end
