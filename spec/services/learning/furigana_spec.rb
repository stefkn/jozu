require "rails_helper"

RSpec.describe Learning::Furigana do
  include CorpusHelper

  before { build_corpus! }

  describe "#render" do
    it "returns an html_safe string" do
      sentence = s["これは必ず必要です。"]
      html = described_class.new(sentence, k["要"]).render("これは必ず必＿です。")
      expect(html).to be_html_safe
    end

    it "wraps segmented words in ruby with their word reading" do
      sentence = s["これは必ず必要です。"]
      html = described_class.new(sentence, k["要"]).render("これは必ず必＿です。")
      expect(html).to include("<ruby>必ず<rt>かならず</rt></ruby>")
    end

    it "reveals the blanked target word's reading on tap" do
      sentence = s["これは必ず必要です。"]
      html = described_class.new(sentence, k["必"]).render("これは＿ず＿＿です。")
      expect(html).to include(%(<span class="kanji-tap is-blank" data-reading="かならず"><ruby>＿ず<rt>かならず</rt></ruby></span>))
      expect(html).to include(%(<span class="kanji-tap is-blank" data-reading="ひつよう"><ruby>＿＿<rt>ひつよう</rt></ruby></span>))
    end

    it "uses the target word's reading (not a per-kanji decomposition) for the blank" do
      sentence = s["これは必ず必要です。"]
      html = described_class.new(sentence, k["必"]).render("これは＿ず＿要です。")
      expect(html).to include(%(data-reading="かならず"><ruby>＿ず<rt>かならず</rt></ruby>))
      expect(html).to include(%(data-reading="ひつよう"><ruby>＿要<rt>ひつよう</rt></ruby>))
    end

    it "falls back to the kanji's primary reading when no word covers it" do
      sak = Kanji.create!(character: "先", grade: 1, frequency_rank: 100, meaning_summary: "before")
      sei = Kanji.create!(character: "生", grade: 1, frequency_rank: 101, meaning_summary: "life")
      Reading.create!(kanji: sak, reading: "さき", kind: "kunyomi")
      Reading.create!(kanji: sei, reading: "せい", kind: "onyomi")

      sentence = s["先生を待っています。"]
      html = described_class.new(sentence, k["待"]).render("先生を＿っています。")
      expect(html).to include("<ruby>先<rt>さき</rt></ruby>")
      expect(html).to include("<ruby>生<rt>せい</rt></ruby>")
      expect(html).to include("を＿っています。")
    end

    it "prefers the kunyomi over the onyomi in the fallback" do
      sei = Kanji.create!(character: "生", grade: 1, frequency_rank: 101, meaning_summary: "life")
      Reading.create!(kanji: sei, reading: "せい", kind: "onyomi")
      Reading.create!(kanji: sei, reading: "いきる", kind: "kunyomi")

      sentence = s["先生を待っています。"]
      html = described_class.new(sentence, k["待"]).render("先生を＿っています。")
      expect(html).to include("<ruby>生<rt>いきる</rt></ruby>")
    end

    it "strips okurigana markers from fallback readings" do
      kokoro = Kanji.create!(character: "心", grade: 1, frequency_rank: 103, meaning_summary: "heart")
      Reading.create!(kanji: kokoro, reading: "-こころ", kind: "kunyomi")

      sentence = s["決心しました。"]
      html = described_class.new(sentence, k["決"]).render("＿心しました。")
      expect(html).not_to include("-こころ")
      expect(html).to include("<ruby>心<rt>こころ</rt></ruby>")
    end
  end

  describe "with stored LLM furigana units" do
    it "prefers the stored context-correct reading over the dictionary heuristic" do
      _kou = Kanji.create!(character: "後", grade: 1, frequency_rank: 200, meaning_summary: "after")
      word = Word.create!(surface: "後", reading: "あと", meaning: "after", frequency_rank: 1)
      sentence = Sentence.create!(japanese: "十日後に試験があります。", translation: "x", source: "curated")
      SentenceWord.create!(sentence:, word:, start_position: 2, end_position: 2)
      sentence.update!(furigana: [ { "start" => 2, "end" => 2, "reading" => "ご" } ])

      html = described_class.new(sentence, k["決"]).render("十日後に＿験があります。")
      expect(html).to include("<ruby>後<rt>ご</rt></ruby>")
      expect(html).not_to include("あと")
    end

    it "still suppresses units overlapping the blanked target" do
      sentence = Sentence.create!(japanese: "十日後に試験があります。", translation: "x", source: "curated")
      sentence.update!(furigana: [
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" },
        { "start" => 4, "end" => 5, "reading" => "しけん" }
      ])

      html = described_class.new(sentence, k["決"]).render("十日＿に試験があります。")
      expect(html).not_to include("<ruby>後<rt>ご</rt></ruby>")
      expect(html).to include("<ruby>十日<rt>とおか</rt></ruby>")
      expect(html).to include("<ruby>試験<rt>しけん</rt></ruby>")
    end

    it "fills gaps in stored units with the dictionary word reading instead of the kanji's primary reading" do
      kou = Kanji.create!(character: "好", grade: 1, frequency_rank: 1, meaning_summary: "like")
      Reading.create!(kanji: kou, reading: "この.む", kind: "kunyomi")
      Reading.create!(kanji: kou, reading: "コウ", kind: "onyomi")
      Word.create!(surface: "好き", reading: "すき", meaning: "to like", frequency_rank: 1)

      sentence = Sentence.create!(japanese: "新聞を読むのが好きです。", translation: "x", source: "curated")
      sentence.update!(furigana: [
        { "start" => 0, "end" => 1, "reading" => "しんぶん" },
        { "start" => 3, "end" => 4, "reading" => "よむ" }
      ])

      html = described_class.new(sentence, kou).render("新聞を読むのが好きです。")
      expect(html).to include("<ruby>好き<rt>すき</rt></ruby>")
      expect(html).not_to include("この")
    end

    it "uses a dictionary word for an uncovered kanji even when no furigana is stored at all" do
      word = Word.create!(surface: "試験", reading: "しけん", meaning: "exam", frequency_rank: 1)
      sentence = Sentence.create!(japanese: "十日後に試験があります。", translation: "x", source: "curated")
      SentenceWord.create!(sentence:, word:, start_position: 4, end_position: 5)

      html = described_class.new(sentence, k["決"]).render("十日後に試験があります。")
      expect(html).to include("<ruby>試験<rt>しけん</rt></ruby>")
    end

    it "wraps a word with a reading but no meaning in a tappable span carrying the reading" do
      sentence = Sentence.create!(japanese: "明日は晴れです。", translation: "x", source: "curated")
      sentence.update!(furigana: [ { "start" => 0, "end" => 1, "reading" => "あした" } ])

      html = described_class.new(sentence, k["決"]).render("明日は晴れです。")
      expect(html).to include(%(<span class="kanji-tap" data-reading="あした"><ruby>明日<rt>あした</rt></ruby></span>))
      expect(html).not_to include("data-meaning")
    end
  end

  describe "with stored kanji meanings" do
    it "wraps whole words in tappable spans carrying their context meaning" do
      sentence = Sentence.create!(japanese: "十日後に試験があります。", translation: "x", source: "curated")
      sentence.update!(furigana: [
        { "start" => 0, "end" => 1, "reading" => "とおか" },
        { "start" => 2, "end" => 2, "reading" => "ご" }
      ])
      sentence.update!(kanji_meanings: [
        { "start" => 0, "end" => 1, "meaning" => "ten days" },
        { "start" => 2, "end" => 2, "meaning" => "after" }
      ])

      html = described_class.new(sentence, k["決"]).render("十日後に試験があります。")
      expect(html).to include(%(<span class="kanji-tap" data-reading="とおか" data-meaning="ten days"><ruby>十日<rt>とおか</rt></ruby></span>))
      expect(html).to include(%(<span class="kanji-tap" data-reading="ご" data-meaning="after"><ruby>後<rt>ご</rt></ruby></span>))
    end

    it "treats a compound word as a single tappable unit" do
      sentence = Sentence.create!(japanese: "東京で友達と会いました。", translation: "x", source: "curated")
      sentence.update!(furigana: [ { "start" => 0, "end" => 1, "reading" => "とうきょう" } ])
      sentence.update!(kanji_meanings: [ { "start" => 0, "end" => 1, "meaning" => "Tokyo" } ])

      html = described_class.new(sentence, k["決"]).render("東京で友達と会いました。")
      expect(html).to include(%(<span class="kanji-tap" data-reading="とうきょう" data-meaning="Tokyo"><ruby>東京<rt>とうきょう</rt></ruby></span>))
      expect(html).not_to include("data-meaning=\"East\"")
      expect(html).not_to include("data-meaning=\"Capital\"")
    end

    it "marks the blanked target word as a tappable hint" do
      sentence = Sentence.create!(japanese: "十日後に試験があります。", translation: "x", source: "curated")
      sentence.update!(furigana: [ { "start" => 4, "end" => 5, "reading" => "しけん" } ])
      sentence.update!(kanji_meanings: [ { "start" => 4, "end" => 5, "meaning" => "exam" } ])

      html = described_class.new(sentence, k["決"]).render("十日後に＿験があります。")
      expect(html).to include(%(<span class="kanji-tap is-blank" data-reading="しけん" data-meaning="exam"><ruby>＿験<rt>しけん</rt></ruby></span>))
    end

    it "leaves kana and un-annotated text untappable" do
      sentence = Sentence.create!(japanese: "これはテストです。", translation: "x", source: "curated")
      sentence.update!(kanji_meanings: [])

      html = described_class.new(sentence, k["決"]).render("これはテストです。")
      expect(html).not_to include("kanji-tap")
    end
  end
end
