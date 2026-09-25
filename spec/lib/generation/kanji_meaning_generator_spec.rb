require "rails_helper"

RSpec.describe Generation::KanjiMeaningGenerator do
  # Unique name: furigana/sentence generator specs define their own fake clients,
  # and a clashing top-level class would silently win for this file.
  class KanjiMeaningFakeOpenAIClient
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

      @responses.shift || { "choices" => [ { "message" => { "content" => '{"後":"after"}' } } ] }
    end
  end

  let(:output_path) { Rails.root.join("tmp", "kanji_meanings_spec_#{SecureRandom.hex(4)}.jsonl") }
  let(:logger) { Logger.new(IO::NULL) }

  before do
    Sentence.delete_all
    create(:sentence, japanese: "十日後に試験があります。", translation: "The exam is in 10 days.", source: "llm")
      .update!(furigana: [
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])
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
      fake = KanjiMeaningFakeOpenAIClient.new
      expect(described_class.new(openai: fake, output_path:, logger:).run!).to eq(1)

      row = rows.first
      expect(row["japanese"]).to eq("十日後に試験があります。")
      expect(row["meanings"]).to eq("後" => "after")
      expect(row["model"]).to eq("openai/gpt-4.1")
    end

    it "extracts JSON wrapped in markdown code fences" do
      fake = KanjiMeaningFakeOpenAIClient.new(responses: [
        { "choices" => [ { "message" => { "content" => "```json\n{\"後\":\"after\"}\n```" } } ] }
      ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(rows.first["meanings"]).to eq("後" => "after")
    end

    it "skips sentences already present in the output file (resume)" do
      File.open(output_path, "a") do |f|
        f.puts(JSON.generate(japanese: "十日後に試験があります。", meanings: { "後" => "after" }, model: "x"))
      end
      fake = KanjiMeaningFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls).to be_empty
      expect(rows.size).to eq(1)
    end

    it "sends response_format json_object and a bounded max_tokens" do
      fake = KanjiMeaningFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:).run!

      params = fake.calls.first
      expect(params[:response_format]).to eq(type: "json_object")
      expect(params[:max_tokens]).to eq(400)
    end

    it "retries a row whose response parses to no usable units, then drops it" do
      invalid = { "choices" => [ { "message" => { "content" => '{"テスト":"てすと"}' } } ] }
      fake = KanjiMeaningFakeOpenAIClient.new(responses: [ invalid, invalid, invalid, invalid ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(described_class::MAX_ATTEMPTS)
      expect(rows).to be_empty
    end

    it "retries transient transport errors then succeeds" do
      fake = KanjiMeaningFakeOpenAIClient.new(errors: [ Faraday::ServerError.new("500 boom") ])
      described_class.new(openai: fake, output_path:, logger:).run!

      expect(fake.calls.size).to eq(2)
      expect(rows.size).to eq(1)
    end

    it "generates concurrently" do
      create(:sentence, japanese: "半年後に帰ります。", translation: "I'll return in half a year.", source: "llm")
        .update!(furigana: [ { "start" => 2, "end" => 2, "reading" => "ご" } ])
      fake = KanjiMeaningFakeOpenAIClient.new
      described_class.new(openai: fake, output_path:, logger:, concurrency: 2).run!

      expect(rows.map { |r| r["japanese"] }).to match_array([ "十日後に試験があります。", "半年後に帰ります。" ])
    end
  end
end
