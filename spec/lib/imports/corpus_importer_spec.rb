require "rails_helper"

RSpec.describe Imports::CorpusImporter do
  include CorpusHelper

  before { build_corpus! }

  describe "#import_kanji!" do
    it "is idempotent" do
      rows = [ { character: "新", grade: 2, frequency_rank: 300, stroke_count: 13,
                meaning: "new", onyomi: %w[しん], kunyomi: %w[あたら] } ]
      importer = described_class.new
      expect { importer.import_kanji!(rows) }.to change(Kanji, :count).by(1)
      expect { importer.import_kanji!(rows) }.not_to change(Kanji, :count)
      expect(Kanji.find_by(character: "新").readings.count).to eq(2)
    end
  end

  describe "#import_words!" do
    it "builds word_kanji links with positions" do
      Kanji.create!(character: "新", frequency_rank: 300, meaning_summary: "new")
      importer = described_class.new
      importer.import_words!([ { surface: "新聞", reading: "しんぶん", meaning: "newspaper",
                                frequency_rank: 1200, jlpt_level: "N4", part_of_speech: "noun" } ])
      word = Word.find_by(surface: "新聞")
      expect(word.word_kanji.count).to eq(1)
      expect(word.word_kanji.first.position).to eq(0)
    end
  end

  describe "#import_sentences!" do
    it "segments and links sentence_words, rejecting invalid rows" do
      importer = described_class.new
      target = Word.find_by(surface: "決める")
      rows = [
        { japanese: "決めるのは難しいですね。", translation: "Deciding is hard.",
          source: "llm", external_id: "row1", generation_version: "m v1 42", target_word: target },
        { japanese: "これは変な文。", translation: "", source: "llm", external_id: "row2",
          generation_version: "m v1 42", target_word: target }
      ]
      stats = importer.import_sentences!(rows)
      expect(stats[:imported]).to eq(1)
      expect(stats[:rejected]).to eq(1)
      sentence = Sentence.find_by(external_id: "row1")
      expect(sentence.sentence_words.map(&:word)).to include(target)
    end
  end
end
