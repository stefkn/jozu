require "rails_helper"

RSpec.describe Learning::DistractorSelector do
  include CorpusHelper

  before { build_corpus! }

  let(:random) { Random.new(1234) }

  describe "validity contract (property-tested over random pools)" do
    def radical_siblings(char)
      kanji = Kanji.find_by(character: char)
      return [] unless kanji&.radical_id

      Kanji.where(radical_id: kanji.radical_id).pluck(:character)
    end
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

    it "always draws distractors from a plausible pool (same reading, same first char, same radical, or shared kanji)" do
      target = w["決める"]
      target_chars = target.surface.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }
      described_class.select_for(question_type: "kana_to_kanji", target:, exclude_ids: [ target.id ],
                                 count: 3, random:).each do |id, _|
        word = Word.find(id)
        same_reading = word.reading == target.reading
        same_first_char = word.surface[0] == target.surface[0]
        similar_first_char = radical_siblings(target.surface[0]).include?(word.surface[0])
        shares_kanji = (word.surface.chars & target_chars).any?
        expect(same_reading || same_first_char || similar_first_char || shares_kanji).to be true
      end
    end

    it "draws sentence_to_kanji distractors from a plausible confusion pool" do
      target = k["決"]
      distractors = described_class.select_for(question_type: "sentence_to_kanji", target:,
                                                exclude_ids: [ target.id ], count: 3, random:)
      expect(distractors).not_to be_empty
      target_readings = target.readings.map(&:reading)
      distractors.each do |id, _|
        kanji = Kanji.find(id)
        shares_reading = (kanji.readings.map(&:reading) & target_readings).any?
        same_radical = kanji.radical_id == target.radical_id
        similar_strokes = target.stroke_count && kanji.stroke_count &&
                          (kanji.stroke_count - target.stroke_count).abs <= 1
        expect(shares_reading || same_radical || similar_strokes).to be true
      end
    end

    it "returns no more than count distractors" do
      expect(described_class.select_for(question_type: "kanji_to_meaning", target: k["決"],
                                        exclude_ids: [ k["決"].id ], count: 3, random:).size).to be <= 3
    end

    it "provides at least one distractor for every corpus target (no single-answer questions)" do
      @k.each_value do |kanji|
        sentence_d = described_class.select_for(question_type: "sentence_to_kanji", target: kanji,
                                                exclude_ids: [ kanji.id ], count: 3, random:)
        expect(sentence_d.size).to be >= 1, "no sentence_to_kanji distractor for #{kanji.character}"
        meaning_d = described_class.select_for(question_type: "kanji_to_meaning", target: kanji,
                                               exclude_ids: [ kanji.id ], count: 3, random:)
        expect(meaning_d.size).to be >= 1, "no kanji_to_meaning distractor for #{kanji.character}"
      end
      @w.each_value do |word|
        d = described_class.select_for(question_type: "kana_to_kanji", target: word,
                                       exclude_ids: [ word.id ], count: 3, random:)
        expect(d.size).to be >= 1, "no kana_to_kanji distractor for #{word.surface}"
      end
    end
  end
end
