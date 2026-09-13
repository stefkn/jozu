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
  end
end
