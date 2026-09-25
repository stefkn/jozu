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

    it "links the kanji to its radical" do
      Radical.create!(character: "水", number: 85, name: "water")
      importer = described_class.new
      importer.import_kanji!([ { character: "決", grade: 3, frequency_rank: 45, stroke_count: 7,
                                 meaning: "decide", onyomi: %w[けつ], kunyomi: %w[き], radical: "水" } ])
      expect(Kanji.find_by(character: "決").radical.character).to eq("水")
    end
  end

  describe "#import_radicals!" do
    it "is idempotent and keyed by character" do
      rows = [ { character: "水", number: 85, name: "water", stroke_count: 4 } ]
      importer = described_class.new
      expect { importer.import_radicals!(rows) }.to change(Radical, :count).by(1)
      expect { importer.import_radicals!(rows) }.not_to change(Radical, :count)
      expect(Radical.find_by(character: "水").name).to eq("water")
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

    it "rejects a second sentence with an identical kanji set" do
      importer = described_class.new
      target = Word.find_by(surface: "決める")
      rows = [
        { japanese: "決めるのは難しいですね。", translation: "One.", source: "llm",
          external_id: "row1", generation_version: "m v1 42", target_word: target },
        { japanese: "決めるのが難しいです。", translation: "Two.", source: "llm",
          external_id: "row2", generation_version: "m v1 42", target_word: target }
      ]
      stats = importer.import_sentences!(rows)
      expect(stats[:imported]).to eq(1)
      expect(stats[:rejected]).to eq(1)
      expect(Sentence.where(external_id: %w[row1 row2]).count).to eq(1)
    end

    it "rejects a row whose target word is missing" do
      importer = described_class.new
      stats = importer.import_sentences!([ { japanese: "決めるのは難しいですね。", translation: "X",
                                             source: "llm", external_id: "row1", generation_version: "m",
                                             target_word: nil } ])
      expect(stats[:imported]).to eq(0)
      expect(stats[:rejected]).to eq(1)
    end

    it "treats a re-import of the same rows as an idempotent no-op, not a duplicate" do
      importer = described_class.new
      target = Word.find_by(surface: "決める")
      rows = [ { japanese: "決めるのは難しいですね。", translation: "Hard.", source: "llm",
                 external_id: "row1", generation_version: "m v1 42", target_word: target } ]
      expect(importer.import_sentences!(rows)[:imported]).to eq(1)
      stats = importer.import_sentences!(rows)
      expect(stats[:imported]).to eq(1)
      expect(stats[:rejected]).to eq(0)
      expect(Sentence.where(external_id: "row1").count).to eq(1)
    end

    it "rejects a new row that duplicates an already-imported kanji set" do
      importer = described_class.new
      target = Word.find_by(surface: "決める")
      importer.import_sentences!([ { japanese: "決めるのは難しいですね。", translation: "Hard.", source: "llm",
                                     external_id: "row1", generation_version: "m", target_word: target } ])
      stats = importer.import_sentences!([ { japanese: "決めるのが難しいです。", translation: "Hard.", source: "llm",
                                             external_id: "row2", generation_version: "m", target_word: target } ])
      expect(stats[:imported]).to eq(0)
      expect(stats[:rejected]).to eq(1)
    end
  end
end
