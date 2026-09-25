require "rails_helper"

RSpec.describe Learning::Progress do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }

  it "returns aggregate counts as before" do
    result = described_class.call(user)
    expect(result.total_kanji).to eq(6)
    expect(result.unknown).to eq(6)
    expect(result.words_unlocked).to eq(0)
  end

  it "groups kanji by bucket with details" do
    UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.9,
                      recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)
    UserKanji.create!(user:, kanji: k["定"], mastery_score: 0.5,
                      recognition_strength: 0.5, reading_strength: 0.5, context_strength: 0.5)
    UserKanji.create!(user:, kanji: k["必"], mastery_score: 0.25,
                      recognition_strength: 0.25, reading_strength: 0.25, context_strength: 0.25)

    result = described_class.call(user)
    expect(result.known).to eq(1)
    expect(result.learning).to eq(1)
    expect(result.weak).to eq(1)
    expect(result.known_kanji.map(&:character)).to eq([ "決" ])
    expect(result.learning_kanji.map(&:character)).to eq([ "定" ])
    expect(result.weak_kanji.map(&:character)).to eq([ "必" ])
    expect(result.unknown_kanji.map(&:character)).to match_array(%w[要 待 持])
    expect(result.known_kanji.first.meaning_summary).to eq("decide")
    expect(result.known_kanji.first.mastery_score).to eq(0.9)
  end

  it "splits words into readable vs learning" do
    UserWord.create!(user:, word: w["決める"], mastery_score: 0.8)
    UserWord.create!(user:, word: w["決定"], mastery_score: 0.3)

    result = described_class.call(user)
    expect(result.words_unlocked).to eq(1)
    expect(result.readable_words.map(&:surface)).to eq([ "決める" ])
    expect(result.learning_words.map(&:surface)).to eq([ "決定" ])
    expect(result.readable_words.first.reading).to eq("きめる")
  end
end
