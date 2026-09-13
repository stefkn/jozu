require "rails_helper"

RSpec.describe Learning::Diagnostic do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }
  let(:now) { Time.current }

  describe "state progression" do
    it "keeps a fresh state until the target count is reached" do
      state = described_class.state_for(user)
      expect(state.finished?).to be false
      expect(state.asked).to eq(0)
    end
  end

  describe "#answer" do
    it "moves to a harder band on a correct answer" do
      state = described_class.state_for(user)
      expect(state.band).to eq(1)
      new_state = described_class.new_state(Learning.config)
      # emulate a correct answer via band logic directly
      diagnostic = described_class.new
      band = diagnostic.send(:next_band, 1, true)
      expect(band).to eq(2)
    end

    it "moves to an easier band on a wrong answer" do
      diagnostic = described_class.new
      expect(diagnostic.send(:next_band, 1, false)).to eq(0)
      expect(diagnostic.send(:next_band, 0, false)).to eq(0)
    end

    it "returns a flashcard until complete" do
      card = described_class.start(user, now:)
      expect(card).not_to be_nil
      expect(card).to be_a(Learning::Flashcard)
      expect(card.front).to be_present
      expect(card.back).to be_present
    end
  end

  describe "#finish!" do
    it "seeds user_kanji and user_words from correct answers" do
      Learning.config.diagnostic_question_count = 1
      q = described_class.start(user, now:)
      described_class.answer(user, word_id: q.word_id, correct: true, confidence: "knew", now:)

      expect(UserKanji.count).to be >= 1
      expect(UserWord.count).to be >= 1
      expect(UserWord.first.mastery_score).to eq(0.6)
      expect(UserKanji.first.recognition_strength).to eq(0.75)
      expect(Review.where(question_type: "kanji_recognition").count).to be >= 1
    end

    it "seeds weak state for wrong answers" do
      Learning.config.diagnostic_question_count = 1
      q = described_class.start(user, now:)
      described_class.answer(user, word_id: q.word_id, correct: false, confidence: "unknown", now:)

      expect(UserKanji.first.recognition_strength).to eq(0.20)
      expect(UserWord.count).to eq(0)
    end

    it "clears the stored state" do
      Learning.config.diagnostic_question_count = 1
      q = described_class.start(user, now:)
      described_class.answer(user, word_id: q.word_id, correct: true, confidence: "knew", now:)
      expect(Rails.cache.read(described_class.state_key(user))).to be_nil
    end
  end
end
