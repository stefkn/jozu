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

    it "introduces one kanji at a time up to the daily cap, then the session ends" do
      scheduler = Learning::Scheduler.new
      3.times do
        question = described_class.call(user, now:)
        expect(question).not_to be_nil
        expect(question.question_type).to eq("kanji_to_meaning")
        scheduler.apply!(UserKanji.find(question.reviewable_id), grade: :good, now:)
      end
      expect(UserKanji.where(user:).count).to eq(3)
      expect(described_class.call(user, now:)).to be_nil
    end

    it "ignores the daily new-kanji cap in practice mode" do
      user.set_setting("practice_mode", true)
      scheduler = Learning::Scheduler.new
      5.times do
        question = described_class.call(user, now:)
        expect(question).not_to be_nil
        scheduler.apply!(UserKanji.find(question.reviewable_id), grade: :good, now:)
      end
      expect(UserKanji.where(user:).count).to eq(5)
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

    it "skips a due reviewable that cannot build a question and serves the next due item" do
      isolated = Kanji.create!(character: "山", grade: 1, frequency_rank: 900, meaning_summary: "mountain")
      dead = UserKanji.create!(user:, kanji: isolated)
      good = UserKanji.create!(user:, kanji: k["決"])
      scheduler = Learning::Scheduler.new
      scheduler.apply!(dead, grade: :again, now: now - 2.hours)
      scheduler.apply!(good, grade: :again, now: now - 1.hour)

      question = described_class.call(user, now:)
      expect(question).not_to be_nil
      expect(question.reviewable_id).to eq(good.id)
    end

    it "returns nil only when nothing is due, no fresh kanji remain, and today's cap is reached" do
      scheduler = Learning::Scheduler.new
      %w[決 必 要].each do |char|
        uk = UserKanji.create!(user:, kanji: k[char])
        scheduler.apply!(uk, grade: :good, now:)
      end
      expect(described_class.call(user, now:)).to be_nil
    end

    it "resumes an interrupted session by serving the oldest un-answered kanji" do
      first = UserKanji.create!(user:, kanji: k["決"])
      described_class.call(user, now:)

      question = described_class.call(user, now:)
      expect(question).not_to be_nil
      expect(question.reviewable_id).to eq(first.id)
    end

    it "skips due number kanji when the user opts out" do
      number = Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
      uk = UserKanji.create!(user:, kanji: number)
      Learning::Scheduler.new.apply!(uk, grade: :again, now: now - 1.hour)
      user.set_setting("skip_number_kanji", true)

      question = described_class.call(user, now:)
      expect(question).not_to be_nil
      served = UserKanji.find(question.reviewable_id)
      expect(served.kanji).not_to eq(number)
    end

    it "never introduces a number kanji when the user opts out" do
      Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
      user.set_setting("skip_number_kanji", true)

      question = described_class.call(user, now:)
      served = UserKanji.find(question.reviewable_id)
      expect(served.kanji.character).not_to eq("一")
    end
  end
end
