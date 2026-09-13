require "rails_helper"

RSpec.describe Learning::DistractorSelector do
  include CorpusHelper

  before { build_corpus! }

  let(:random) { Random.new(1234) }

  describe "validity contract (property-tested over random pools)" do
    it "returns unique distractors distinct from the target for kana_to_kanji" do
      20.times do
        target = Word.where(reading: "きめる").first || w["決める"]
        distractors = described_class.select_for(question_type: "kana_to_kanji", target:,
                                                 exclude_ids: [ target.id ], count: 3, random:)
        ids = distractors.map(&:first)
        expect(ids.uniq.size).to eq(ids.size)
        expect(ids).not_to include(target.id)
        expect(ids.size).to be <= 3
      end
    end

    it "always draws distractors from a plausible pool (same reading)" do
      target = w["決める"]
      described_class.select_for(question_type: "kana_to_kanji", target:, exclude_ids: [ target.id ],
                                 count: 3, random:).each do |id, _|
        expect(Word.find(id).reading).to eq(target.reading)
      end
    end

    it "draws sentence_to_kanji distractors from the reading/radical confusion pool" do
      target = k["決"]
      described_class.select_for(question_type: "sentence_to_kanji", target:, exclude_ids: [ target.id ],
                                 count: 3, random:).each do |id, _|
        kanji = Kanji.find(id)
        expect(kanji.readings.map(&:reading)).to include("けつ", "き")
      end
    end

    it "returns no more than count distractors" do
      expect(described_class.select_for(question_type: "kanji_to_meaning", target: k["決"],
                                        exclude_ids: [ k["決"].id ], count: 3, random:).size).to be <= 3
    end
  end
end
