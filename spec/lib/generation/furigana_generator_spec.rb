require "rails_helper"

RSpec.describe Generation::FuriganaGenerator do
  # Unique name: sentence_generator_spec defines its own top-level FakeOpenAIClient,
  # and the later-loaded class would silently win for this file.
  class FuriganaFakeOpenAIClient
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

      @responses.shift || { "choices" => [ { "message" => { "content" => DEFAULT_RESPONSE } } ] }
    end
  end

  # Full kanji coverage for both sentences used in this file, so the default
  # response always passes the generator's completeness gate.
  DEFAULT_RESPONSE = '{"十日":"とおか","後":"ご","試験":"しけん","半年":"はんとし","帰り":"かえり"}'

  let(:output_path) { Rails.root.join("tmp", "furigana_spec_#{SecureRandom.hex(4)}.jsonl") }
  let(:logger) { Logger.new(IO::NULL) }

  before do
    Sentence.delete_all
    create(:sentence, japanese: "十日後に試験があります。", translation: "The exam is in 10 days.", source: "llm")
  end

  after do
    output_path.delete if output_path.exist?
  end

  def rows
    return [] unless output_path.exist?

    output_path.readlines(chomp: true).map { |line| JSON.parse(line) }
  end

  describe "#run!" do
    it "appends one JSONL row per sentence" do
      fake = FuriganaFakeOpenAIClient.new
      expect(described_class.new(openai: fake, output_path:, logger:).run!).to eq(1)

      row = rows.first
      expect(row["japanese"]).to eq("十日後に試験があります。")
      expect(row["furigana"]).to eq([
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])
      expect(row["model"]).to eq("openai/gpt-4.1")
    end

    it "extracts JSON wrapped in markdown code fences" do
      fake = FuriganaFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => "```json\n{\"十日\":\"とおか\",\"後\":\"ご\",\"試験\":\"しけん\"}\n```" } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(rows.first["furigana"]).to eq([
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])
    end

    it "skips sentences already present in the output file (resume)" do
      File.open(output_path, "a") do |f|
        f.puts(JSON.generate(japanese: "十日後に試験があります。", furigana: { "後" => "ご" }, model: "x"))
      end
      fake = FuriganaFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls).to be_empty
      expect(rows.size).to eq(1)
    end

    it "sends response_format json_object and a bounded max_tokens" do
      fake = FuriganaFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:).run!

      params = fake.calls.first
      expect(params[:response_format]).to eq(type: "json_object")
      expect(params[:max_tokens]).to eq(300)
    end

    it "retries a row whose response parses to no usable units, then drops it" do
      fake = FuriganaFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => '{"テスト":"てすと"}' } } ] },
        { "choices" => [ { "message" => { "content" => "not json" } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(2)
      expect(rows).to be_empty
    end

    it "retries a partial-coverage response and accepts a complete retry" do
      fake = FuriganaFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => '{"後":"ご"}' } } ] },
        { "choices" => [ { "message" => { "content" => '{"十日":"とおか","後":"ご","試験":"しけん"}' } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(2)
      expect(rows.size).to eq(1)
      expect(rows.first["furigana"]).to include("start" => 2, "end" => 2, "reading" => "ご")
    end

    it "drops a row that never achieves full kanji coverage" do
      fake = FuriganaFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => '{"後":"ご"}' } } ] },
        { "choices" => [ { "message" => { "content" => '{"試験":"しけん"}' } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(2)
      expect(rows).to be_empty
    end

    it "repairs coverage gaps from the words table and stores a complete row" do
      Word.create!(surface: "十日", reading: "とおか", meaning: "ten days", frequency_rank: 1)
      Word.create!(surface: "試験", reading: "しけん", meaning: "exam", frequency_rank: 2)
      fake = FuriganaFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => '{"後":"ご"}' } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(1)
      expect(rows.size).to eq(1)
      expect(rows.first["furigana"]).to eq([
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])
    end

    it "retries transient transport errors then succeeds" do
      fake = FuriganaFakeOpenAIClient.new(errors: [ Faraday::ServerError.new("500 boom") ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(2)
      expect(rows.size).to eq(1)
    end

    it "generates concurrently" do
      create(:sentence, japanese: "半年後に帰ります。", translation: "I'll return in half a year.", source: "llm")
      fake = FuriganaFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:, concurrency: 2).run!

      expect(rows.map { |r| r["japanese"] }).to match_array([ "十日後に試験があります。", "半年後に帰ります。" ])
    end
  end
end
