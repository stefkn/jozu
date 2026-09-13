# Builds a deterministic mini-corpus for service specs (plan §11: "unit tests run
# against fixtures, not the real bank"). Provides just enough kanji/words/sentences
# for the algorithms to produce questions with plausible distractors.
module CorpusHelper
  def build_corpus!
    kanji = {
      "決" => { grade: 3, freq: 45, meaning: "decide" },
      "定" => { grade: 3, freq: 46, meaning: "fix, establish" },
      "必" => { grade: 4, freq: 47, meaning: "certain, necessary" },
      "要" => { grade: 4, freq: 48, meaning: "need, essential" },
      "待" => { grade: 3, freq: 43, meaning: "wait" },
      "持" => { grade: 3, freq: 44, meaning: "hold, have" }
    }

    @k = {}
    kanji.each do |char, data|
      k = Kanji.create!(character: char, grade: data[:grade], frequency_rank: data[:freq],
                        meaning_summary: data[:meaning])
      Reading.create!(kanji: k, reading: "けつ", kind: "onyomi") if char == "決"
      Reading.create!(kanji: k, reading: "き", kind: "kunyomi") if char == "決"
      Reading.create!(kanji: k, reading: "てい", kind: "onyomi") if char == "定"
      Reading.create!(kanji: k, reading: "ひつ", kind: "onyomi") if char == "必"
      Reading.create!(kanji: k, reading: "よう", kind: "onyomi") if char == "要"
      Reading.create!(kanji: k, reading: "たい", kind: "onyomi") if char == "待"
      Reading.create!(kanji: k, reading: "じ", kind: "onyomi") if char == "持"
      @k[char] = k
    end

    words = {
      "決める" => [ "きめる", "to decide", 1 ],
      "決定" => [ "けってい", "decision", 2 ],
      "必ず" => [ "かならず", "certainly", 3 ],
      "必要" => [ "ひつよう", "necessary", 4 ],
      "待つ" => [ "まつ", "to wait", 5 ],
      "持つ" => [ "もつ", "to hold", 6 ]
    }
    @w = {}
    words.each do |surface, (reading, meaning, freq)|
      w = Word.create!(surface:, reading:, meaning:, frequency_rank: freq, part_of_speech: "noun")
      surface.chars.each_with_index do |char, index|
        next unless @k[char]

        WordKanji.create!(word: w, kanji: @k[char], position: index)
      end
      @w[surface] = w
    end

    sentences = {
      "明日までに決めます。" => "I will decide by tomorrow.",
      "これは必ず必要です。" => "This is certainly necessary.",
      "先生を待っています。" => "I am waiting for the teacher.",
      "決定は後で連絡します。" => "I will inform you of the decision later.",
      "この本を持っています。" => "I have this book.",
      "必ず来てください。" => "Please be sure to come.",
      "決心しました。" => "I made up my mind."
    }
    @s = {}
    sentences.each do |ja, en|
      s = Sentence.create!(japanese: ja, translation: en, difficulty: 3, source: "curated")
      @s[ja] = s
    end

    @segmenter = Segmentation::LongestMatch.build(words.keys)
    words.each_key do |surface|
      target = @w[surface]
      @s.each do |ja, sentence|
        @segmenter.segment(ja).each do |token|
          next unless token.surface == surface

          SentenceWord.create!(sentence:, word: target, start_position: token.start_position,
                               end_position: token.end_position)
        end
      end
    end
  end

  attr_reader :k, :w, :s

  def make_user
    @user ||= create(:user)
  end
end
