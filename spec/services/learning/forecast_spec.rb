require "rails_helper"

RSpec.describe Learning::Forecast do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }
  let(:scheduler) { Learning::Scheduler.new }

  def due_row(char, at:)
    uk = UserKanji.create!(user:, kanji: k[char])
    scheduler.apply!(uk, grade: :again, now: now - 1.hour)
    uk.update!(due_at: at)
    uk
  end

  it "buckets due items by day, counting overdue as today" do
    due_row("決", at: now - 1.hour)
    due_row("定", at: now + 1.day)
    due_row("必", at: now + 10.days)

    result = described_class.call(user, now:)
    expect(result.days.size).to eq(7)
    expect(result.days[0].count).to eq(1)
    expect(result.days[1].count).to eq(1)
    expect(result.days[2..].map(&:count)).to all(eq(0))
    expect(result.later_count).to eq(1)
    expect(result.total).to eq(2)
  end

  it "excludes graduated, suspended and card-less items" do
    due_row("決", at: now - 1.hour).update!(graduated_at: now)
    due_row("定", at: now - 1.hour).update!(suspended_at: now)
    UserKanji.create!(user:, kanji: k["必"])

    result = described_class.call(user, now:)
    expect(result.total).to eq(0)
    expect(result.later_count).to eq(0)
  end

  it "excludes skipped number kanji" do
    number = Kanji.create!(character: "一", grade: 1, frequency_rank: 2, meaning_summary: "one")
    uk = UserKanji.create!(user:, kanji: number)
    scheduler.apply!(uk, grade: :again, now: now - 1.hour)
    user.set_setting("skip_number_kanji", true)

    expect(described_class.call(user, now:).total).to eq(0)
  end

  it "counts due words too" do
    uw = UserWord.create!(user:, word: w["決める"])
    scheduler.apply!(uw, grade: :again, now: now - 1.hour)

    expect(described_class.call(user, now:).days[0].count).to eq(1)
  end
end
