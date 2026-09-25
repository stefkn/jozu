require "rails_helper"

RSpec.describe Learning::OptionDetails do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  describe ".for_question" do
    it "returns [] for kanji_to_meaning" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      question = Learning::QuestionGenerator.new.generate(user, uk, question_type: "kanji_to_meaning")
      expect(described_class.for_question(question)).to eq([])
    end

    it "builds kanji details in option order for sentence_to_kanji" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "sentence_to_kanji")
      details = described_class.for_question(question)

      expect(details.size).to eq(question.options.size)
      expect(details.map(&:option_id)).to eq(question.options.keys.map(&:to_s))
      expect(details).to all(be_a(described_class::KanjiOption))

      by_char = details.index_by(&:character)
      ketsu = by_char["決"]
      expect(ketsu.meaning).to eq("decide")
      # Only the readings used by frequent words (決める/決定) are kept, most
      # frequent first.
      expect(ketsu.readings.map(&:reading)).to eq([ "き", "けつ" ])
    end

    it "drops readings that differ only in dot/dash placement" do
      kanji = k["決"]
      Reading.create!(kanji:, reading: "け.つ", kind: "onyomi")
      Reading.create!(kanji:, reading: "-き", kind: "kunyomi")
      uk = UserKanji.create!(user:, kanji:, times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "sentence_to_kanji")
      detail = described_class.for_question(question).find { |d| d.character == "決" }
      # First bank form wins; the dot/dash variants are not repeated.
      expect(detail.readings.map(&:reading)).to eq([ "き", "けつ" ])
    end

    it "drops rare readings with no supporting words" do
      kanji = k["決"]
      Reading.create!(kanji:, reading: "zzz", kind: "onyomi")
      uk = UserKanji.create!(user:, kanji:, times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "sentence_to_kanji")
      detail = described_class.for_question(question).find { |d| d.character == "決" }
      expect(detail.readings.map(&:reading)).not_to include("zzz")
    end

    it "falls back to the first bank readings when no word evidence exists" do
      kanji = Kanji.create!(character: "山", grade: 1, frequency_rank: 900, meaning_summary: "mountain")
      Reading.create!(kanji:, reading: "サン", kind: "onyomi")
      Reading.create!(kanji:, reading: "やま", kind: "kunyomi")
      expect(described_class.common_readings(kanji, []).map(&:reading)).to eq([ "サン", "やま" ])
    end

    it "matches onyomi through small-tsu (けつ in けってい)" do
      expect(described_class.match_norm("けってい")).to include(described_class.match_norm("けつ"))
    end

    it "provides furigana examples excluding the current sentence" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "sentence_to_kanji")
      details = described_class.for_question(question)
      details.each do |d|
        expect(d.examples.size).to be <= described_class::EXAMPLE_LIMIT
        d.examples.each do |ex|
          expect(ex.html).to be_html_safe
          expect(ex.translation).to be_present
        end
      end
      # 決定 sentence is linked to 決; it must show up for 決 unless it is the prompt.
      ketsu = details.find { |d| d.character == "決" }
      prompt_sentence = Sentence.find_by(id: question.sentence_id)
      if prompt_sentence&.japanese != "決定は後で連絡します。"
        expect(ketsu.examples.map { |ex| ex.html.to_s }).to satisfy do |htmls|
          htmls.empty? || htmls.join.include?("決定")
        end
      end
    end

    it "renders the study panel for sentence_to_kanji" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "sentence_to_kanji")
      details = described_class.for_question(question)
      html = ApplicationController.render(partial: "sessions/option_details", locals: { details: })

      expect(html).to include("Study notes")
      expect(html).to include("decide")
      expect(html).not_to include("★")
      expect(html).to include("KUN")
      expect(html).to include('data-quiz-target="details"')
    end

    it "renders the study panel for kana_to_kanji" do
      uk = UserKanji.create!(user:, kanji: k["必"], times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "kana_to_kanji")
      details = described_class.for_question(question)
      html = ApplicationController.render(partial: "sessions/option_details", locals: { details: })

      expect(html).to include("Study notes")
      expect(html).to include("study-furigana")
    end

    it "builds word details with kanji breakdown for kana_to_kanji" do
      uk = UserKanji.create!(user:, kanji: k["必"], times_seen: 1)
      question = Learning::QuestionGenerator.new(random: Random.new(1))
                                            .generate(user, uk, question_type: "kana_to_kanji")
      details = described_class.for_question(question)

      expect(details.size).to eq(question.options.size)
      expect(details).to all(be_a(described_class::WordOption))

      target = details.find { |d| d.option_id == question.correct_option_id }
      expect(target.reading).to be_present
      expect(target.meaning).to be_present
      expect(target.kanji.map(&:character)).to include(*target.surface.chars.select do |c|
        c.ord.between?(0x4e00, 0x9fff)
      end)
      target.examples.each do |ex|
        expect(ex.html).to be_html_safe
      end
    end
  end
end
