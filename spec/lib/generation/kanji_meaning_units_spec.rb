require "rails_helper"

RSpec.describe Generation::KanjiMeaningUnits do
  let(:furigana) do
    [
      { "start" => 0, "end" => 1, "reading" => "とおか" },
      { "start" => 2, "end" => 2, "reading" => "ご" },
      { "start" => 4, "end" => 5, "reading" => "しけん" }
    ]
  end

  describe ".call" do
    it "aligns each word's meaning to its furigana unit span" do
      units = described_class.call("十日後に試験があります。", { "十日" => "ten days", "後" => "after", "試験" => "exam" }, furigana)
      expect(units).to eq([
        { "start" => 0, "end" => 1, "meaning" => "ten days" },
        { "start" => 2, "end" => 2, "meaning" => "after" },
        { "start" => 4, "end" => 5, "meaning" => "exam" }
      ])
    end

    it "keeps a compound word as one unit rather than splitting its characters" do
      units = described_class.call("東京で友達と会いました。", { "東京" => "Tokyo", "友達" => "friend" },
                                   [ { "start" => 0, "end" => 1, "reading" => "とうきょう" },
                                     { "start" => 3, "end" => 4, "reading" => "ともだち" } ])
      expect(units).to eq([
        { "start" => 0, "end" => 1, "meaning" => "Tokyo" },
        { "start" => 3, "end" => 4, "meaning" => "friend" }
      ])
    end

    it "ignores words with no furigana unit, non-English meanings, and over-long meanings" do
      units = described_class.call("本を読みました。", { "本" => "book", "を" => "particle", "読" => "読む" },
                                   [ { "start" => 0, "end" => 0, "reading" => "ほん" } ])
      expect(units).to eq([ { "start" => 0, "end" => 0, "meaning" => "book" } ])

      long = described_class.call("本", { "本" => "a very long explanation that goes on and on for ages" },
                                  [ { "start" => 0, "end" => 0, "reading" => "ほん" } ])
      expect(long).to eq([])
    end

    it "handles nil and non-hash input" do
      expect(described_class.call("本を読みました。", nil, furigana)).to eq([])
      expect(described_class.call("本を読みました。", "not a hash", furigana)).to eq([])
      expect(described_class.call("本を読みました。", {}, nil)).to eq([])
    end
  end
end
