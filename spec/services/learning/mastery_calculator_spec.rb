require "rails_helper"

RSpec.describe Learning::MasteryCalculator do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:user_kanji) { UserKanji.create!(user:, kanji: k["決"]) }

  describe "#update!" do
    it "applies the confidence-bucket delta to the question dimension" do
      Learning::MasteryCalculator.new.update!(user_kanji, question_type: "sentence_to_kanji",
                                             correct: true, confidence: "knew", now: Time.current)

      expect(user_kanji.reload.context_strength).to be_within(0.001).of(0.14)
      expect(user_kanji.mastery_score).to be_within(0.001).of(0.14 * 0.3)
    end

    it "maps kana_to_kanji and kanji_to_meaning to the recognition dimension" do
      uk = UserKanji.create!(user:, kanji: k["定"])
      %w[kana_to_kanji kanji_to_meaning].each do |type|
        uk.update!(recognition_strength: 0.0)
        Learning::MasteryCalculator.new.update!(uk, question_type: type, correct: true,
                                               confidence: "unknown", now: Time.current)
        expect(uk.reload.recognition_strength).to be_within(0.001).of(0.03)
      end
    end

    it "clamps the strength to [0, 1]" do
      uk = UserKanji.create!(user:, kanji: k["必"], context_strength: 0.99)
      Learning::MasteryCalculator.new.update!(uk, question_type: "sentence_to_kanji",
                                             correct: true, confidence: "instant", now: Time.current)
      expect(uk.reload.context_strength).to eq(1.0)
    end

    it "updates counters and timestamps independently" do
      now = Time.current
      Learning::MasteryCalculator.new.update!(user_kanji, question_type: "kanji_to_meaning",
                                             correct: true, confidence: "knew", now:)
      Learning::MasteryCalculator.new.update!(user_kanji, question_type: "kanji_to_meaning",
                                             correct: false, confidence: "thought", now:)

      expect(user_kanji.reload.times_seen).to eq(2)
      expect(user_kanji.times_correct).to eq(1)
      expect(user_kanji.times_incorrect).to eq(1)
      expect(user_kanji.first_seen_at).to be_within(1.second).of(now)
      expect(user_kanji.last_seen_at).to be_within(1.second).of(now)
    end

    it "updates word mastery directly for user_words" do
      user_word = UserWord.create!(user:, word: w["決める"])
      Learning::MasteryCalculator.new.update!(user_word, question_type: "kana_to_kanji",
                                             correct: true, confidence: "instant", now: Time.current)
      expect(user_word.reload.mastery_score).to be_within(0.001).of(0.14)
    end
  end
end
