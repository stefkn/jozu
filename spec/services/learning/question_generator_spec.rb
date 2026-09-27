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

    it "builds kanji_to_reading with the surface as prompt and readings as options" do
      uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1)
      question = described_class.new.generate(user, uk, question_type: "kanji_to_reading")
      expect(question).not_to be_nil
      expect(question.question_type).to eq("kanji_to_reading")
      expect(question.prompt).to eq(w["決める"].surface)
      expect(question.options[question.correct_option_id]).to eq("きめる")
      expect(question.options.values.uniq.size).to eq(question.options.size)
      expect(question.options.values).not_to include(nil)
    end

    it "builds kanji_to_reading for a user_word target" do
      uw = UserWord.create!(user:, word: w["待つ"], mastery_score: 0.3)
      question = described_class.new.generate(user, uw, question_type: "kanji_to_reading")
      expect(question).not_to be_nil
      expect(question.prompt).to eq("待つ")
      expect(question.options[question.correct_option_id]).to eq("まつ")
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
        %w[kanji_to_meaning sentence_to_kanji kana_to_kanji kanji_to_reading].each do |type|
          question = described_class.new(random: Random.new(1)).generate(user, uk, question_type: type)
          next if question.nil?

          expect(question.options.size).to be >= described_class::MIN_OPTIONS
        end
      end
    end

    context "contrast drills" do
      def record_wrong(type:, correct_id:, chosen_id:, times: 1)
        uk = UserKanji.find_or_create_by!(user:, kanji: k["決"])
        times.times do
          Review.create!(
            user:, reviewable: uk, question_type: type, grade: "again",
            distractors: [ chosen_id ], answer_id: chosen_id.to_s,
            correct_option_id: correct_id.to_s,
            presented_at: Time.current, answered_at: Time.current, correct: false
          )
        end
      end

      it "serves a 2-option drill once a confusion pair spikes" do
        record_wrong(type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id, times: 2)
        uk = UserKanji.find_by(user:, kanji: k["決"])
        uk.update!(times_seen: 3)
        question = described_class.new.generate(user, uk, question_type: "sentence_to_kanji")

        expect(question).not_to be_nil
        expect(question.drill?).to be true
        expect(question.options.size).to eq(2)
        expect(question.options.keys.map(&:to_s)).to contain_exactly(k["決"].id.to_s, k["持"].id.to_s)
        expect(question.distractors.map(&:to_s)).to eq([ k["持"].id.to_s ])
      end

      it "serves a 2-option kana drill for a spiking word pair" do
        record_wrong(type: "kana_to_kanji", correct_id: w["決める"].id, chosen_id: w["決定"].id, times: 2)
        uk = UserKanji.find_by(user:, kanji: k["決"])
        uk.update!(times_seen: 3)
        question = described_class.new.generate(user, uk, question_type: "kana_to_kanji")

        expect(question.drill?).to be true
        expect(question.options.keys.map(&:to_s)).to contain_exactly(w["決める"].id.to_s, w["決定"].id.to_s)
      end

      it "keeps the full static pool below the contrast threshold" do
        record_wrong(type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id, times: 1)
        uk = UserKanji.find_by(user:, kanji: k["決"])
        uk.update!(times_seen: 3)
        question = described_class.new.generate(user, uk, question_type: "sentence_to_kanji")

        expect(question.drill?).to be false
        # Mini-corpus static pool for 決 is just [定]; the single confusion
        # still biases it first via confuser preference.
        expect(question.options.keys.map(&:to_s)).to contain_exactly(
          k["決"].id.to_s, k["持"].id.to_s, k["定"].id.to_s
        )
      end

      it "skips the drill when contrast is disabled" do
        record_wrong(type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id, times: 2)
        uk = UserKanji.find_by(user:, kanji: k["決"])
        uk.update!(times_seen: 3)
        question = described_class.new.generate(user, uk, question_type: "sentence_to_kanji", contrast: false)

        expect(question.drill?).to be false
        expect(question.options.keys.map(&:to_s)).to contain_exactly(
          k["決"].id.to_s, k["持"].id.to_s, k["定"].id.to_s
        )
      end
    end
  end
end
