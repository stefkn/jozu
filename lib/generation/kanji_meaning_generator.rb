module Generation
  # Offline batch LLM generation of context-aware English definitions for every
  # kanji in every sentence (the meaning companion to jozu:generate_furigana).
  # Writes a versioned JSONL at vendor/data/generated_kanji_meanings.jsonl; each
  # row maps a sentence to { kanji => meaning } so the runtime Furigana service
  # can render tap-to-show definitions.
  #
  # Resumable: sentences whose content hash already appears in the output file
  # are skipped. Rows that parse to no usable units get one retry at a higher
  # temperature. 429 rate limits are handled with a long backoff so the run
  # survives OpenRouter's per-minute caps instead of dying.
  class KanjiMeaningGenerator
    include Response

    PROMPT_VERSION = "v1"
    OUTPUT_PATH = Rails.root.join("vendor/data/generated_kanji_meanings.jsonl")
    MAX_ATTEMPTS = 4
    RETRY_TEMPERATURE = 0.7
    RETRY_MAX = 8
    RETRY_SLEEP_429 = 20.0

    # @param model [String] OpenRouter model slug.
    # @param concurrency [Integer] number of parallel in-flight requests.
    # @param openai [Object, nil] injectable OpenAI-compatible client (tests).
    # @param output_path [Pathname] where rows are appended (tests).
    def initialize(model: ENV.fetch("JOZU_KANJI_MEANING_MODEL", "openai/gpt-4.1"),
                   temperature: 0.0, max_tokens: 400, json_mode: true,
                   concurrency: 1, openai: nil, output_path: OUTPUT_PATH, logger: Logger.new($stdout))
      @model = model
      @temperature = temperature
      @max_tokens = max_tokens
      @json_mode = json_mode
      @concurrency = [ concurrency.to_i, 1 ].max
      @openai = openai
      @output_path = output_path
      @logger = logger
    end

    # @return [Integer] number of new rows appended to the JSONL.
    def run!(limit: nil)
      existing = load_existing_keys
      sentences = Sentence.order(:id).filter_map do |s|
        furigana = s.furigana
        next unless furigana.present?

        { japanese: s.japanese, translation: s.translation, furigana: }
      end.reject { |unit| existing.key?(unit_key(unit)) }
      sentences = sentences.first(limit) if limit
      @logger.info "Skipping #{existing.size} already-annotated sentences" if existing.any?

      count = generate_all(sentences)
      @logger.info "Annotated #{count} sentences (#{sentences.size - count} failures)."
      count
    end

    private

    def client
      @client ||= @openai || Generation::Client.build
    end

    def generate_all(sentences)
      return generate_sequential(sentences) if @concurrency == 1

      generate_concurrent(sentences)
    end

    def generate_sequential(sentences)
      count = 0
      sentences.each { |unit| count += 1 if generate_one(unit) }
      count
    end

    def generate_concurrent(sentences)
      queue = Queue.new
      sentences.each { |unit| queue << unit }

      mutex = Mutex.new
      total = 0
      workers = @concurrency.times.map do
        Thread.new do
          local = 0
          while (unit = pop(queue))
            local += 1 if generate_one(unit)
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
      MAX_ATTEMPTS.times do |attempt|
        result = request_meanings(unit, temperature: attempt.zero? ? @temperature : RETRY_TEMPERATURE)
        next unless result

        units = KanjiMeaningUnits.call(unit[:japanese], result, unit[:furigana])
        return append(unit, result) unless units.empty?

        @logger.warn "No usable meanings for #{unit[:japanese][0, 20]}..."
      end
      false
    rescue StandardError => e
      @logger.warn "Dropping #{unit[:japanese][0, 20]}... (#{e.class})"
      false
    end

    def request_meanings(unit, temperature:)
      params = {
        model: @model,
        temperature:,
        max_tokens: @max_tokens,
        messages: [ { role: "user", content: build_prompt(unit) } ]
      }
      params[:response_format] = { type: "json_object" } if @json_mode

      response = chat_with_retries(params)
      log_usage(response)
      parse_json_response(response.dig("choices", 0, "message", "content"), logger: @logger)
    end

    def chat_with_retries(params)
      attempts = 0
      begin
        attempts += 1
        client.chat(parameters: params)
      rescue *Response::RETRYABLE_ERRORS => e
        raise if attempts >= RETRY_MAX

        delay = e.is_a?(Faraday::TooManyRequestsError) ? RETRY_SLEEP_429 : Response::RETRY_BACKOFF_SECONDS * attempts
        @logger.warn "Request failed (attempt #{attempts}/#{RETRY_MAX}): #{e.class} #{e.message}"
        sleep(delay)
        retry
      end
    end

    def log_usage(response)
      usage = response.dig("usage")
      return unless usage

      @logger.info "usage: #{usage['prompt_tokens']} prompt / #{usage['completion_tokens']} completion tokens"
    end

    def build_prompt(unit)
      surfaces = unit[:furigana].map { |u| unit[:japanese][u["start"].to_i..u["end"].to_i] }
      <<~PROMPT
        For each word below (as used in this Japanese sentence), give its English meaning in context.
        Return a JSON object mapping each word to a concise English meaning (1–4 words).
        - Use the meaning of the whole word in this context (e.g. 東京 is "Tokyo", not "east"+"capital"; 日本語 is "Japanese language").
        - Words are exact substrings of the sentence.
        - Cover every word in the list.
        Words: #{surfaces.join(", ")}
        Sentence: #{unit[:japanese]}
        Translation: #{unit[:translation]}
        Return strict JSON.
      PROMPT
    end

    def append(unit, meaning_map)
      row = {
        japanese: unit[:japanese],
        translation: unit[:translation],
        meanings: meaning_map,
        model: @model,
        prompt_version: PROMPT_VERSION,
        generated_at: Time.current.utc.iso8601
      }
      @output_path.dirname.mkpath
      File.open(@output_path, "a") { |f| f.puts(JSON.generate(row)) }
      @logger.info "Annotated #{unit[:japanese][0, 20]}..."
      true
    end

    def load_existing_keys
      return {} unless @output_path.exist?

      File.readlines(@output_path, chomp: true).each_with_object({}) do |line, keys|
        row = JSON.parse(line) rescue next
        keys[Digest::SHA256.hexdigest(row["japanese"].to_s)] = true
      end
    end

    def unit_key(unit)
      Digest::SHA256.hexdigest(unit[:japanese].to_s)
    end
  end
end
