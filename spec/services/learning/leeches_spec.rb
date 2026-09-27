require "rails_helper"

RSpec.describe Learning::Leeches do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  def kanji_row(char, seen:, incorrect:, mastery: 0.3)
    UserKanji.create!(user:, kanji: k[char], times_seen: seen,
                      times_incorrect: incorrect, times_correct: seen - incorrect,
                      mastery_score: mastery)
  end

  it "ranks leeches worst-first, breaking rate ties by miss count" do
    kanji_row("決", seen: 10, incorrect: 8)
    kanji_row("持", seen: 10, incorrect: 7).update!(suspended_at: Time.current)
    kanji_row("定", seen: 10, incorrect: 5)
    UserWord.create!(user:, word: w["決める"], times_seen: 6,
                     times_incorrect: 3, times_correct: 3, mastery_score: 0.3)
    kanji_row("必", seen: 10, incorrect: 2)
    kanji_row("要", seen: 3, incorrect: 3)
    kanji_row("待", seen: 10, incorrect: 9).update!(graduated_at: Time.current)

    leeches = described_class.call(user)
    expect(leeches.map(&:label)).to eq([ "決", "持", "定", "決める" ])
    expect(leeches.map(&:suspended)).to eq([ false, true, false, false ])

    top = leeches.first
    expect(top.kind).to eq(:kanji)
    expect(top.character).to eq("決")
    expect(top.failure_rate).to be_within(0.001).of(0.8)

    word = leeches.last
    expect(word.kind).to eq(:word)
    expect(word.character).to be_nil
    expect(word.sublabel).to eq("きめる")
  end

  it "honours a custom limit" do
    kanji_row("決", seen: 10, incorrect: 8)
    kanji_row("定", seen: 10, incorrect: 7)
    kanji_row("必", seen: 10, incorrect: 6)

    config = Learning::Config.new
    config.leech_limit = 2
    expect(described_class.call(user, config:).size).to eq(2)
  end

  it "lists graduated items separately, most recently retired first" do
    first = kanji_row("決", seen: 10, incorrect: 1, mastery: 0.9)
    first.update!(graduated_at: 2.days.ago)
    second = kanji_row("定", seen: 10, incorrect: 1, mastery: 0.9)
    second.update!(graduated_at: 1.day.ago)

    retired = described_class.graduated(user)
    expect(retired.map(&:label)).to eq([ "定", "決" ])
    expect(retired.first.mastery).to be_within(0.001).of(0.9)
  end
end
