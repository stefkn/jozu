require "rails_helper"

RSpec.describe Generation::Validation do
  include CorpusHelper

  before { build_corpus! }

  let(:segmenter) { Segmentation::LongestMatch.build(Word.pluck(:surface)) }
  let(:target) { Word.find_by(surface: "決める") }

  describe ".validate" do
    it "accepts a natural sentence containing the target word" do
      result = described_class.validate(
        sentence: "決めるのは難しいですね。", target_word: target, en: "Deciding is hard, isn't it?", segmenter:
      )
      expect(result.valid).to be true
      expect(result.reasons).to be_empty
    end

    it "rejects a missing translation" do
      result = described_class.validate(sentence: "明日までに決めます。", target_word: target, en: "", segmenter:)
      expect(result.reasons).to include("missing translation")
    end

    it "rejects out-of-band lengths" do
      result = described_class.validate(sentence: "決めます。", target_word: target, en: "x", segmenter:)
      expect(result.reasons).to include(a_string_matching(/wrong length/))
    end

    it "rejects missing sentence-final punctuation" do
      result = described_class.validate(sentence: "明日までに決めます", target_word: target, en: "x", segmenter:)
      expect(result.reasons).to include("missing sentence-final punctuation")
    end

    it "rejects a sentence without the target word" do
      result = described_class.validate(sentence: "今日は晴れです。", target_word: target, en: "x", segmenter:)
      expect(result.reasons).to include("target word not found")
    end

    it "rejects other kanji outside the frequency budget" do
      Kanji.create!(character: "鬱", frequency_rank: 4000, meaning_summary: "melancholy")
      result = described_class.validate(sentence: "鬱の決め方。", target_word: target, en: "x", segmenter:)
      expect(result.reasons).to include("other kanji exceed frequency budget")
    end
  end

  describe ".duplicate?" do
    it "flags identical kanji sets" do
      expect(described_class.duplicate?("明日までに決めます。", "決めます明日までに。")).to be true
    end

    it "allows distinct sentences" do
      expect(described_class.duplicate?("明日までに決めます。", "先生を待っています。")).to be false
    end
  end
end
