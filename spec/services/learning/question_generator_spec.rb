require "rails_helper"

RSpec.describe Learning::QuestionGenerator do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  describe "#generate" do
    it "builds kana_to_kanji for a user_kanji target" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = described_class.new.generate(user, uk, question_type: "kana_to_kanji")
      expect(question).not_to be_nil
      expect(question.question_type).to eq("kana_to_kanji")
      expect(question.prompt).to eq("きめる")
      expect(question.options).to include(question.correct_option_id)
    end

    it "builds kana_to_kanji for a user_word target without a kanji method" do
      uw = UserWord.create!(user:, word: w["決める"], mastery_score: 0.3)
      question = described_class.new.generate(user, uw, question_type: "kana_to_kanji")
      expect(question).not_to be_nil
      expect(question.question_type).to eq("kana_to_kanji")
      expect(question.reviewable_type).to eq("UserWord")
      expect(question.prompt).to eq("きめる")
    end

    it "builds sentence_to_kanji via the target kanji" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = described_class.new.generate(user, uk, question_type: "sentence_to_kanji")
      expect(question).not_to be_nil
      expect(question.question_type).to eq("sentence_to_kanji")
      expect(question.prompt).to include("＿")
      expect(question.prompt_html).to be_present
      expect(question.prompt_html).to be_html_safe
    end

    it "builds kanji_to_meaning" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      question = described_class.new.generate(user, uk, question_type: "kanji_to_meaning")
      expect(question).not_to be_nil
      expect(question.question_type).to eq("kanji_to_meaning")
      expect(question.prompt).to eq("決")
      expect(question.options[question.correct_option_id]).to eq("decide")
    end

    it "makes the kanji_to_meaning prompt tappable with the kanji's reading but not its meaning" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      question = described_class.new.generate(user, uk, question_type: "kanji_to_meaning")
      expect(question.prompt_html).to include("kanji-tap")
      expect(question.prompt_html).to include('data-reading="きめる"')
      expect(question.prompt_html).not_to include("data-meaning")
      expect(question.prompt_html).not_to include("decide")
    end

    it "shuffles options so the correct answer is not always first" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      positions = 20.times.map do |i|
        question = described_class.new(random: Random.new(i)).generate(user, uk, question_type: "kanji_to_meaning")
        question.options.keys.index(question.correct_option_id)
      end
      expect(positions.uniq.size).to be > 1
    end

    it "refuses to emit a single-answer question when no distractor is plausible" do
      isolated = Kanji.create!(character: "山", grade: 1, frequency_rank: 900, meaning_summary: "mountain")
      uk = UserKanji.create!(user:, kanji: isolated)

      question = described_class.new.generate(user, uk, question_type: "kanji_to_meaning")
      expect(question).to be_nil
    end

    it "builds at least MIN_OPTIONS options for every corpus target" do
      @k.each_value do |kanji|
        uk = UserKanji.create!(user:, kanji:)
        %w[kanji_to_meaning sentence_to_kanji kana_to_kanji].each do |type|
          question = described_class.new(random: Random.new(1)).generate(user, uk, question_type: type)
          next if question.nil?

          expect(question.options.size).to be >= described_class::MIN_OPTIONS
        end
      end
    end
  end
end
