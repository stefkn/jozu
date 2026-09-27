require "rails_helper"

RSpec.describe Learning::SessionProgress do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }

  it "starts empty when there is no work" do
    result = described_class.call(user, now:)
    expect(result.answered).to eq(0)
    expect(result.percent).to eq(0)
  end

  it "fills against the actual work when it is smaller than the target" do
    uk = UserKanji.create!(user:, kanji: k["決"])
    Learning::Scheduler.new.apply!(uk, grade: :again, now: now - 1.hour)

    # 1 due + 2 new-kanji slots (one slot already used by today's row).
    result = described_class.call(user, now:)
    expect(result.answered).to eq(0)
    expect(result.total).to eq(3)
    expect(result.percent).to eq(0)

    2.times do
      Review.create!(user:, reviewable: uk, question_type: "kana_to_kanji", grade: "good",
                     presented_at: now, answered_at: now, correct: true)
    end
    result = described_class.call(user, now:)
    expect(result.total).to eq(5)
    expect(result.percent).to eq(40)
  end

  it "pins at the daily target when the backlog is larger" do
    scheduler = Learning::Scheduler.new
    Kanji.all.each do |kanji|
      uk = UserKanji.create!(user:, kanji:)
      scheduler.apply!(uk, grade: :again, now: now - 1.hour)
    end
    uk = user.user_kanji.first
    10.times do
      Review.create!(user:, reviewable: uk, question_type: "kana_to_kanji", grade: "good",
                     presented_at: now, answered_at: now, correct: true)
    end

    result = described_class.call(user, now:)
    expect(result.answered).to eq(10)
    expect(result.total).to eq(10)
    expect(result.percent).to eq(100)
  end
end
