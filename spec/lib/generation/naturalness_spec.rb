require "rails_helper"

RSpec.describe Generation::Naturalness do
  class FakeNaturalnessClient
    attr_reader :calls

    def initialize(scores:)
      @scores = scores
      @calls = []
    end

    def chat(parameters:)
      @calls << parameters
      score = @scores.shift
      { "choices" => [ { "message" => { "content" => JSON.generate(score: score) } } ] }
    end
  end

  let(:logger) { Logger.new(IO::NULL) }

  describe "#rate" do
    it "returns the model score" do
      client = FakeNaturalnessClient.new(scores: [ 4 ])
      naturalness = described_class.new(openai: client, logger:)

      expect(naturalness.rate("これは自然な文です。")).to eq(4)
      expect(client.calls.first[:max_tokens]).to eq(50)
    end

    it "retries once at higher temperature on an unparseable reply, then fails closed" do
      client = FakeNaturalnessClient.new(scores: [ "NaN", 3 ])
      naturalness = described_class.new(openai: client, logger:)

      expect(naturalness.rate("これは自然な文です。")).to eq(3)
      temperatures = client.calls.map { |c| c[:temperature] }
      expect(temperatures).to eq([ 0.0, 1.0 ])
    end

    it "returns nil when no score is ever produced" do
      client = FakeNaturalnessClient.new(scores: [ nil, nil ])
      naturalness = described_class.new(openai: client, logger:)

      expect(naturalness.rate("これは自然な文です。")).to be_nil
    end
  end

  describe "#keep?" do
    it "keeps sentences at or above the threshold" do
      client = FakeNaturalnessClient.new(scores: [ 3, 4, 2 ])
      naturalness = described_class.new(openai: client, logger:)

      expect(naturalness.keep?("文A。")).to be true
      expect(naturalness.keep?("文B。")).to be true
      expect(naturalness.keep?("文C。")).to be false
    end
  end
end
