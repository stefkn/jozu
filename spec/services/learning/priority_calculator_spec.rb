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

    def with_number_kanji
      number = Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
      word = Word.create!(surface: "一つ", reading: "ひとつ", meaning: "one (thing)", frequency_rank: 1)
      WordKanji.create!(word:, kanji: number, position: 0)
      number
    end

    it "excludes number kanji when the user opts out" do
      number = with_number_kanji
      user.set_setting("skip_number_kanji", true)

      result = described_class.new.top_unseen(user, limit: 10)
      expect(result).not_to include(number)
      expect(result).to include(k["決"])
    end

    it "keeps number kanji when the user has not opted out" do
      number = with_number_kanji
      result = described_class.new.top_unseen(user, limit: 10)
      expect(result).to include(number)
    end
  end
end
