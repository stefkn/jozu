require "rails_helper"

RSpec.describe Learning::Session do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }

  it "counts due reviews" do
    uk = UserKanji.create!(user:, kanji: k["決"])
    Learning::Scheduler.new.apply!(uk, grade: :again, now: now - 1.hour)
    summary = described_class.summary(user, now:)
    expect(summary.reviews_count).to eq(1)
  end

  it "excludes due number kanji when the user opts out" do
    number = Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
    uk = UserKanji.create!(user:, kanji: number)
    Learning::Scheduler.new.apply!(uk, grade: :again, now: now - 1.hour)
    user.set_setting("skip_number_kanji", true)

    summary = described_class.summary(user, now:)
    expect(summary.reviews_count).to eq(0)
  end

  it "counts new kanji but not number kanji when opted out" do
    number = Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
    user.set_setting("skip_number_kanji", true)

    summary = described_class.summary(user, now:)
    expect(summary.new_kanji_count).to be > 0
    # 一 must not be among the pool of eligible unseen kanji.
    eligible = Kanji.where.not(character: Kanji::NUMBER_KANJI)
    expect(eligible).not_to include(number)
  end

  it "counts new kanji beyond the daily cap in practice mode" do
    user.set_setting("practice_mode", true)
    3.times { |i| UserKanji.create!(user:, kanji: k.values[i], created_at: now - i.hours, times_seen: 1) }

    summary = described_class.summary(user, now:)
    expect(summary.new_kanji_count).to eq(Kanji.count - 3)
  end
end
