require "rails_helper"

RSpec.describe Learning::Scheduler do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:user_kanji) { UserKanji.create!(user:, kanji: k["決"]) }

  describe ".grade_for" do
    it "maps a wrong answer to again regardless of confidence" do
      expect(described_class.grade_for(correct: false, confidence: "knew", response_time_ms: 500)).to eq(:again)
    end

    it "maps unknown confidence to again even when correct" do
      expect(described_class.grade_for(correct: true, confidence: "unknown", response_time_ms: 500)).to eq(:again)
    end

    it "maps guessed to hard even when correct" do
      expect(described_class.grade_for(correct: true, confidence: "guessed", response_time_ms: 500)).to eq(:hard)
    end

    it "maps slow correct answers to hard" do
      expect(described_class.grade_for(correct: true, confidence: "knew", response_time_ms: 5_000)).to eq(:hard)
    end

    it "maps instant + fast to easy" do
      expect(described_class.grade_for(correct: true, confidence: "instant", response_time_ms: 800)).to eq(:easy)
    end

    it "maps correct + normal to good" do
      expect(described_class.grade_for(correct: true, confidence: "knew", response_time_ms: 2_000)).to eq(:good)
    end

    it "does not penalise a slow sentence answer as hard" do
      expect(described_class.grade_for(correct: true, confidence: "knew", response_time_ms: 8_000,
                                       question_type: "sentence_to_kanji")).to eq(:good)
    end

    it "still penalises the same slowness on a single-kanji question" do
      expect(described_class.grade_for(correct: true, confidence: "knew", response_time_ms: 8_000,
                                       question_type: "kana_to_kanji")).to eq(:hard)
    end

    it "penalises an extremely slow sentence answer" do
      expect(described_class.grade_for(correct: true, confidence: "knew", response_time_ms: 20_000,
                                       question_type: "sentence_to_kanji")).to eq(:hard)
    end
  end

  describe "#apply!" do
    it "persists the fsrs card into srs_state and sets due_at" do
      now = Time.current
      described_class.new.apply!(user_kanji, grade: :good, now:)

      uk = user_kanji.reload
      expect(uk.srs_state).to include("state", "stability", "difficulty")
      expect(uk.due_at).to be > now
    end

    it "returns previous and new interval" do
      now = Time.current
      result = described_class.new.apply!(user_kanji, grade: :easy, now:)
      expect(result.previous_interval).to eq(0.0)
      expect(result.new_interval).to be > 0
      expect(result.grade).to eq("easy")
    end

    it "advances due_at further on a second good review" do
      scheduler = described_class.new
      first = scheduler.apply!(user_kanji, grade: :good, now: Time.current).new_interval
      second = scheduler.apply!(user_kanji, grade: :good, now: Time.current + 1.hour).new_interval
      expect(second).to be > first
    end

    it "round-trips srs_state through jsonb" do
      now = Time.current
      scheduler = described_class.new
      scheduler.apply!(user_kanji, grade: :good, now:)
      reloaded = UserKanji.find(user_kanji.id)
      scheduler.apply!(reloaded, grade: :hard, now: now + 1.hour)
      expect(reloaded.reload.due_at).to be > now + 1.hour
    end
  end

  describe "#due?" do
    it "is false for a record with no srs state" do
      expect(described_class.new.due?(user_kanji, now: Time.current)).to be false
    end

    it "is true once a card is scheduled and past due" do
      scheduler = described_class.new
      scheduler.apply!(user_kanji, grade: :good, now: Time.current)
      future = user_kanji.reload.due_at + 1.minute
      expect(scheduler.due?(user_kanji.reload, now: future)).to be true
    end

    it "is false before the card is due" do
      scheduler = described_class.new
      scheduler.apply!(user_kanji, grade: :good, now: Time.current)
      expect(scheduler.due?(user_kanji.reload, now: Time.current)).to be false
    end

    it "is false for graduated and suspended items no matter how overdue" do
      scheduler = described_class.new
      scheduler.apply!(user_kanji, grade: :good, now: Time.current)

      user_kanji.update!(graduated_at: Time.current)
      expect(scheduler.due?(user_kanji, now: Time.current + 1.year)).to be false

      user_kanji.update!(graduated_at: nil, suspended_at: Time.current)
      expect(scheduler.due?(user_kanji, now: Time.current + 1.year)).to be false
    end
  end

  describe "graduation" do
    let(:config) do
      Learning::Config.new.tap { |c| c.graduation_min_interval = 12.hours }
    end
    let(:scheduler) { described_class.new(config:) }

    def strong_kanji(char = "決")
      UserKanji.create!(user:, kanji: k[char], mastery_score: 0.9,
                        recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)
    end

    it "graduates a well-known item once its interval matures" do
      uk = strong_kanji
      scheduler.apply!(uk, grade: :easy, now: Time.current)
      expect(uk.reload.graduated_at).to be_present
    end

    it "does not graduate a weak item even on a long interval" do
      uk = UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.1)
      scheduler.apply!(uk, grade: :easy, now: Time.current)
      expect(uk.reload.graduated_at).to be_nil
    end

    it "does not graduate on a short interval" do
      uk = strong_kanji
      scheduler.apply!(uk, grade: :good, now: Time.current)
      expect(uk.reload.graduated_at).to be_nil
    end

    it "does not graduate a suspended item" do
      uk = strong_kanji
      uk.update!(suspended_at: Time.current)
      scheduler.apply!(uk, grade: :easy, now: Time.current)
      expect(uk.reload.graduated_at).to be_nil
    end
  end
end
