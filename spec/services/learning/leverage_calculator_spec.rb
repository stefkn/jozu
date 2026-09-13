require "rails_helper"

RSpec.describe Learning::LeverageCalculator do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  describe "#leverage_score" do
    it "returns a score in [0, 1]" do
      score = described_class.new.leverage_score(k["決"], user)
      expect(score).to be_between(0.0, 1.0)
    end

    it "is higher when the learner knows the words containing the kanji" do
      baseline = described_class.new.leverage_score(k["決"], user)
      UserWord.create!(user:, word: w["決める"], mastery_score: 0.9)
      UserWord.create!(user:, word: w["決定"], mastery_score: 0.8)
      known = described_class.new.leverage_score(k["決"], user)
      expect(known).to be > baseline
    end
  end

  describe "#unlock_count" do
    it "counts words the learner already knows" do
      UserWord.create!(user:, word: w["決める"], mastery_score: 0.9)
      expect(described_class.new.unlock_count(k["決"], user)).to eq(1)
    end

    it "excludes words below the known threshold" do
      UserWord.create!(user:, word: w["決める"], mastery_score: 0.2)
      expect(described_class.new.unlock_count(k["決"], user)).to eq(0)
    end
  end

  describe "#word_weight" do
    it "uses the user's mastery for known words" do
      UserWord.create!(user:, word: w["決める"], mastery_score: 0.8)
      expect(described_class.new.word_weight(w["決める"], user)).to eq(0.8)
    end

    it "uses a frequency prior for unseen words" do
      expect(described_class.new.word_weight(w["決める"], user)).to be_between(0.0, 0.5)
    end
  end
end
