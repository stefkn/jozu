require "rails_helper"

RSpec.describe Learning::PriorityCalculator do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  describe "#call" do
    it "ranks higher frequency kanji above lower frequency" do
      high = described_class.new.call(user, kanji: k["決"])
      low = described_class.new.call(user, kanji: k["必"])
      expect(high.priority).to be > low.priority
    end

    it "uses a neutral uncertainty for unseen items" do
      result = described_class.new.call(user, kanji: k["決"])
      expect(result.uncertainty).to eq(0.6)
    end

    it "peaks uncertainty at p = 0.5" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 2, times_correct: 1)
      result = described_class.new.call(user, kanji: k["決"])
      expect(result.uncertainty).to be_within(0.001).of(1.0)
      expect(result.priority).to be > 0
    end

    it "drops uncertainty for a consistent performer" do
      UserKanji.create!(user:, kanji: k["決"], times_seen: 8, times_correct: 8)
      result = described_class.new.call(user, kanji: k["決"])
      expect(result.uncertainty).to be < 0.6
    end
  end

  describe "#top_unseen" do
    it "excludes seen kanji and respects the limit" do
      UserKanji.create!(user:, kanji: k["決"])
      result = described_class.new.top_unseen(user, limit: 3)
      expect(result.size).to eq(3)
      expect(result).not_to include(k["決"])
      expect(result.map(&:id).uniq.size).to eq(3)
    end
  end
end
