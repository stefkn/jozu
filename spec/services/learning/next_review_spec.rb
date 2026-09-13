require "rails_helper"

RSpec.describe Learning::NextReview do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }

  describe "#call" do
    it "returns a kanji_to_meaning question for a new kanji" do
      question = described_class.call(user, now:)
      expect(question).not_to be_nil
      expect(question.question_type).to eq("kanji_to_meaning")
      expect(question.reviewable_type).to eq("UserKanji")
      expect(question.correct_option_id).not_to be_nil
    end

    it "stores the question for idempotent answer verification" do
      question = described_class.call(user, now:)
      stored = Learning::QuestionStore.fetch(question.token)
      expect(stored).to eq(question)
    end

    it "caps new kanji at three per session" do
      3.times { described_class.call(user, now:) }
      fresh = UserKanji.where(user:, times_seen: 0).count
      expect(fresh).to eq(3)
      expect(described_class.call(user, now:)).to be_nil
    end

    it "surfaces a due review before introducing new kanji" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      Learning::Scheduler.new.apply!(uk, grade: :good, now: now - 2.days)

      question = described_class.call(user, now:)
      expect(question.reviewable_id).to eq(uk.id)
    end

    it "picks the earliest-due review when several are due" do
      early = UserKanji.create!(user:, kanji: k["決"])
      later = UserKanji.create!(user:, kanji: k["必"])
      scheduler = Learning::Scheduler.new
      scheduler.apply!(early, grade: :good, now: now - 3.days)
      scheduler.apply!(later, grade: :good, now: now - 1.day)

      question = described_class.call(user, now:)
      expect(question.reviewable_id).to eq(early.id)
    end

    it "returns nil when nothing is due and the new-kanji cap is reached" do
      3.times { described_class.call(user, now:) }
      expect(described_class.call(user, now:)).to be_nil
    end
  end
end
