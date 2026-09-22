require "rails_helper"

RSpec.describe Generation::SentenceGenerator do
  # A stand-in for OpenAI::Client that records request params and replays
  # scripted responses / errors.
  class FakeOpenAIClient
    attr_reader :calls

    def initialize(responses: [], errors: [])
      @responses = responses
      @errors = errors
      @calls = []
    end

    def chat(parameters:)
      @calls << parameters
      error = @errors.shift
      raise error if error

      @responses.shift || { "choices" => [ { "message" => { "content" => '{"ja":"テストです。","en":"It is a test."}' } } ] }
    end
  end

  let(:output_path) { Rails.root.join("tmp", "generator_spec_#{SecureRandom.hex(4)}.jsonl") }
  let(:logger) { Logger.new(IO::NULL) }

  before do
    kanji = create(:kanji, character: "決")
    word = create(:word, surface: "決める", reading: "きめる", meaning: "to decide")
    WordKanji.create!(word:, kanji:, position: 0)
  end

  after do
    output_path.delete if output_path.exist?
  end

  def rows
    return [] unless output_path.exist?

    output_path.readlines(chomp: true).map { |line| JSON.parse(line) }
  end

  describe "#run!" do
    it "appends one JSONL row per (word × kanji) unit" do
      fake = FakeOpenAIClient.new
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(1)

      row = rows.first
      expect(row).to include("word" => "決める", "kanji" => "決")
      expect(row).to include("ja" => "テストです。", "en" => "It is a test.")
      expect(row["model"]).to eq("anthropic/claude-sonnet-4")
    end

    it "extracts JSON wrapped in markdown code fences" do
      fake = FakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => "```json\n{\"ja\":\"テストです。\",\"en\":\"It is a test.\"}\n```" } } ] }
      ])
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(1)
      expect(rows.first["ja"]).to eq("テストです。")
    end

    it "skips units already present in the output file (resume)" do
      File.open(output_path, "a") do |f|
        f.puts(JSON.generate(word: "決める", kanji: "決", ja: "以前の文です。", en: "An older sentence.", model: "x"))
      end
      fake = FakeOpenAIClient.new
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(0)
      expect(fake.calls).to be_empty
      expect(rows.size).to eq(1)
    end

    it "does not send response_format/seed by default" do
      fake = FakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:).run!

      params = fake.calls.first
      expect(params).not_to have_key(:response_format)
      expect(params).not_to have_key(:seed)
      expect(params[:max_tokens]).to eq(500)
    end

    it "sends response_format and seed when enabled" do
      fake = FakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:, json_mode: true, send_seed: true).run!

      params = fake.calls.first
      expect(params[:response_format]).to eq(type: "json_object")
      expect(params[:seed]).to eq(42)
    end

    it "retries transient transport errors then succeeds" do
      fake = FakeOpenAIClient.new(errors: [ Faraday::ServerError.new("500 boom"), Faraday::TimeoutError.new("timeout") ])
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(1)
      expect(fake.calls.size).to eq(3)
      expect(rows.size).to eq(1)
    end

    it "does not retry non-transient 4xx errors" do
      fake = FakeOpenAIClient.new(errors: [ Faraday::BadRequestError.new("400 bad request") ])
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect { generator.run! }.to raise_error(Faraday::BadRequestError)
      expect(fake.calls.size).to eq(1)
    end

    it "applies the limit to units, not words" do
      kanji_a = create(:kanji, character: "持")
      kanji_b = create(:kanji, character: "待")
      word = create(:word, surface: "持つ", reading: "もつ", meaning: "to hold")
      WordKanji.create!(word:, kanji: kanji_a, position: 0)
      WordKanji.create!(word:, kanji: kanji_b, position: 1)
      fake = FakeOpenAIClient.new

      generator = described_class.new(openai: fake, output_path:, logger:)
      expect(generator.run!(limit: 1)).to eq(1)
      expect(fake.calls.size).to eq(1)
    end

    it "generates concurrently, writing one row per unit" do
      kanji_a = create(:kanji, character: "持")
      kanji_b = create(:kanji, character: "待")
      word = create(:word, surface: "持つ", reading: "もつ", meaning: "to hold")
      WordKanji.create!(word:, kanji: kanji_a, position: 0)
      WordKanji.create!(word:, kanji: kanji_b, position: 1)
      fake = FakeOpenAIClient.new

      generator = described_class.new(openai: fake, output_path:, logger:, concurrency: 2)
      expect(generator.run!).to eq(3)
      expect(rows.map { |r| r["word"] }).to match_array(%w[決める 持つ 持つ])
    end

    it "does not append rows with a blank translation" do
      fake = FakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => '{"ja":"テストです。","en":""}' } } ] }
      ])
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(0)
      expect(rows).to be_empty
    end

    it "drops rows whose model response is not JSON" do
      fake = FakeOpenAIClient.new(responses: [ { "choices" => [ { "message" => { "content" => "not json at all" } } ] } ])
      generator = described_class.new(openai: fake, output_path:, logger:)

      expect(generator.run!).to eq(0)
      expect(rows).to be_empty
    end
  end
end
