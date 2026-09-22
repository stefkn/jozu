require "rails_helper"

RSpec.describe Generation::FuriganaUnits do
  describe ".call" do
    it "converts a surface => reading map into position units" do
      units = described_class.call("十日後に試験があります。", { "十日" => "とおか", "後" => "ご", "試験" => "しけん" })
      expect(units).to eq([
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])
    end

    it "ignores keys that are not substrings of the sentence" do
      units = described_class.call("本を読みました。", { "存在しない" => "そんざい" })
      expect(units).to be_empty
    end

    it "ignores pure-kana keys and non-kana readings" do
      units = described_class.call("本を読みました。", { "を" => "を", "本" => "123" })
      expect(units).to be_empty
    end

    it "rejects overlapping groups, keeping the longest" do
      units = described_class.call("日本語を勉強します。", { "日本" => "にほん", "語" => "ご", "日本語" => "にほんご" })
      expect(units.map { |u| u["reading"] }).to eq([ "にほんご" ])
    end

    it "handles nil and non-hash input" do
      expect(described_class.call("本を読みました。", nil)).to eq([])
      expect(described_class.call("本を読みました。", "not a hash")).to eq([])
    end

    it "returns an empty array when no kanji is covered" do
      units = described_class.call("これはテストです。", { "テスト" => "てすと" })
      expect(units).to be_empty
    end
  end

  describe ".kanji_positions" do
    it "returns character indices of every kanji" do
      expect(described_class.kanji_positions("新聞を読むのが好きです。")).to eq([ 0, 1, 3, 7 ])
    end

    it "returns an empty array for kana-only text" do
      expect(described_class.kanji_positions("これはテストです。")).to eq([])
    end
  end

  describe ".covers?" do
    it "is true when every kanji position is covered" do
      units = described_class.call("新聞を読むのが好きです。",
                                   { "新聞" => "しんぶん", "読む" => "よむ", "好き" => "すき" })
      expect(described_class.covers?("新聞を読むのが好きです。", units)).to be true
    end

    it "is false when any kanji is uncovered" do
      units = described_class.call("新聞を読むのが好きです。",
                                   { "新聞" => "しんぶん", "読む" => "よむ" })
      expect(described_class.covers?("新聞を読むのが好きです。", units)).to be false
    end
  end
end
