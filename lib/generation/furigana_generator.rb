module Generation
  # Offline batch LLM furigana generation (context-correct readings). Writes a
  # versioned JSONL file at vendor/data/generated_furigana.jsonl; each row maps a
  # sentence to { word => reading } so the runtime Furigana service can render
  # context-correct ruby instead of dictionary word-readings (which misread
  # suffix compounds like 十日後 -> あと instead of ご).
  #
  # Resumable: sentences whose content hash already appears in the output file
  # are skipped, so an interrupted batch restarts with the same command. Rows
  # that parse to no usable units get one retry at a higher temperature.
  #
  # Completeness gate: a row is only appended when EVERY kanji in the sentence is
  # covered. The model's output is repaired against the words table (the model
  # systematically skips single-kanji okurigana verbs like 行き/大きい), retried
  # at a higher temperature, and only then dropped — partial readings are never
  # stored, since they would misread compounds (好 -> このむ instead of すき).
  class FuriganaGenerator
    include Response

    PROMPT_VERSION = "v1"
    OUTPUT_PATH = Rails.root.join("vendor/data/generated_furigana.jsonl")
    MAX_ATTEMPTS = 2
    RETRY_TEMPERATURE = 0.7
    RETRY_MAX = 8
    # OpenRouter rate-limits gpt-4.1 aggressively; a short burst trips a per-minute
    # cap that a 2/4/6s backoff can't outlast. Sleep ~20s on 429 so the cap resets.
    RETRY_SLEEP_429 = 20.0

    # @param model [String] OpenRouter model slug.
    # @param concurrency [Integer] number of parallel in-flight requests.
    # @param openai [Object, nil] injectable OpenAI-compatible client (tests).
    # @param output_path [Pathname] where rows are appended (tests).
    def initialize(model: ENV.fetch("JOZU_FURIGANA_MODEL", "openai/gpt-4.1"),
                   temperature: 0.0, max_tokens: 300, json_mode: true,
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
      sentences = Sentence.order(:id).map { |s| { japanese: s.japanese, translation: s.translation } }
                          .reject { |unit| existing.key?(unit_key(unit)) }
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
      sentences.each do |unit|
        count += 1 if generate_one(unit)
      end
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
        result = request_furigana(unit, temperature: attempt.zero? ? @temperature : RETRY_TEMPERATURE)
        next unless result

        units = FuriganaUnits.call(unit[:japanese], result)
        units = repair_gaps(unit[:japanese], units)
        if FuriganaUnits.covers?(unit[:japanese], units)
          return append(unit, units)
        end

        @logger.warn "Incomplete furigana for #{unit[:japanese][0, 20]}... (#{missing_kanji(unit, units)})"
      end
      false
    rescue StandardError => e
      @logger.warn "Dropping #{unit[:japanese][0, 20]}... (#{e.class})"
      false
    end

    # The model reliably annotates compounds but systematically skips single
    # kanji verbs/adjectives carrying okurigana (行き, 大きい, 好き). Fill those
    # gaps from the words table so coverage is complete before storing.
    def repair_gaps(japanese, units)
      covered = units.flat_map { |u| (u["start"].to_i..u["end"].to_i).to_a }
      fills = DictionaryReadings.fill(japanese, covered:).map do |st, en, rd|
        { "start" => st, "end" => en, "reading" => rd }
      end
      (units + fills).sort_by { |u| u["start"].to_i }
    end

    def missing_kanji(unit, units)
      covered = units.flat_map { |u| (u["start"].to_i..u["end"].to_i).to_a }
      missing = FuriganaUnits.kanji_positions(unit[:japanese]) - covered
      missing.map { |i| unit[:japanese].chars[i] }.uniq.join
    end

    def request_furigana(unit, temperature:)
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
      <<~PROMPT
        Annotate the reading (furigana) of EVERY kanji in this Japanese sentence, without exception.
        Return a JSON object mapping each kanji-bearing word (or group) in the sentence to its reading in hiragana.
        - Keys must be exact contiguous substrings of the sentence that contain at least one kanji.
        - Values must be the reading of that word exactly as pronounced IN THIS SENTENCE (e.g. 後 is "ご" in "十日後", "あと" alone).
        - Do NOT skip single-kanji verbs/adjectives that carry okurigana. Example: in "新聞を読むのが好きです。" annotate "読む" -> "よむ" AND "好き" -> "すき". In "毎日会社へ行きます。" annotate "行き" -> "いき". In "家の近くに大きい本屋があります。" annotate "大きい" -> "おおきい".
        - Cover every kanji in the sentence; do not include pure-kana words or particles.
        Example: for "十日後に試験があります。" return {"十日": "とおか", "後": "ご", "試験": "しけん"}
        Sentence: #{unit[:japanese]}
        Translation: #{unit[:translation]}
        Return strict JSON.
      PROMPT
    end

    def append(unit, units)
      row = {
        japanese: unit[:japanese],
        translation: unit[:translation],
        furigana: units,
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
        keys[row["content_hash"] || Digest::SHA256.hexdigest(row["japanese"].to_s)] = true
      end
    end

    def unit_key(unit)
      Digest::SHA256.hexdigest(unit[:japanese].to_s)
    end
  end
end
