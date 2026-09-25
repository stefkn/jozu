require "rails_helper"

RSpec.describe Imports::ReferenceConverter do
  let(:sources_dir) { Pathname.new(Dir.mktmpdir("jozu-sources")) }
  let(:output_dir) { Pathname.new(Dir.mktmpdir("jozu-output")) }
  let(:converter) { described_class.new(sources_dir:, output_dir:) }

  after do
    FileUtils.remove_entry(sources_dir)
    FileUtils.remove_entry(output_dir)
  end

  before do
    write_source("radicals.json", {
      "metadata" => { "count" => 1 },
      "radicals" => [
        { "radical" => "水", "stroke_count" => 4, "classical_number" => 85,
          "meanings" => [ "water" ], "kanji" => [ "決", "法" ] },
        { "radical" => "夊", "stroke_count" => 3, "classical_number" => 35,
          "meanings" => [], "kanji" => [ "夏" ] }
      ]
    })
    write_source("kanji.json", {
      "metadata" => {},
      "kanji" => [
        { "character" => "決", "grade" => 3, "frequency" => 45, "stroke_count" => 7,
          "radical" => { "classical" => 85 },
          "meanings" => { "en" => [ "decide" ] },
          "readings" => { "on" => [ "ケツ" ], "kun" => [ "き.める" ] } },
        { "character" => "鬱", "grade" => 9, "frequency" => 4000, "stroke_count" => 29,
          "radical" => { "classical" => 85 },
          "meanings" => { "en" => [ "melancholy" ] },
          "readings" => { "on" => [ "ウツ" ], "kun" => [] } },
        { "character" => "曜", "grade" => 2, "frequency" => 95, "stroke_count" => 18,
          "radical" => { "classical" => 72 },
          "meanings" => { "en" => [ "weekday" ] },
          "readings" => { "on" => [ "ヨウ" ], "kun" => [] } },
        { "character" => "火", "grade" => 1, "frequency" => 574, "stroke_count" => 4,
          "radical" => { "classical" => 86 },
          "meanings" => { "en" => [ "fire" ] },
          "readings" => { "on" => [ "カ" ], "kun" => [ "ひ" ] } },
        { "character" => "稀", "grade" => 9, "frequency" => 2500, "stroke_count" => 12,
          "radical" => { "classical" => 115 },
          "meanings" => { "en" => [ "rare" ] },
          "readings" => { "on" => [ "キ" ], "kun" => [ "まれ" ] } }
      ]
    })
    write_source("words.json", {
      "metadata" => {},
      "words" => [
        { "id" => "1", "kanji" => [ { "common" => true, "text" => "決める" } ],
          "kana" => [ { "common" => true, "text" => "きめる" } ],
          "sense" => [ { "partOfSpeech" => [ "v1" ], "gloss" => [ { "lang" => "eng", "text" => "to decide" } ] } ],
          "jlpt_waller" => "N5" },
        { "id" => "2", "kanji" => [ { "common" => true, "text" => "鬱" } ],
          "kana" => [ { "common" => true, "text" => "うつ" } ],
          "sense" => [ { "partOfSpeech" => [ "n" ], "gloss" => [ { "lang" => "eng", "text" => "depression" } ] } ],
          "jlpt_waller" => nil },
        { "id" => "3", "kanji" => [ { "common" => true, "text" => "火曜日" } ],
          "kana" => [ { "common" => true, "text" => "かようび" } ],
          "sense" => [ { "partOfSpeech" => [ "n" ], "gloss" => [ { "lang" => "eng", "text" => "Tuesday" } ] } ],
          "jlpt_waller" => "N5" },
        { "id" => "4", "kanji" => [ { "common" => true, "text" => "決稀" } ],
          "kana" => [ { "common" => true, "text" => "けっき" } ],
          "sense" => [ { "partOfSpeech" => [ "n" ], "gloss" => [ { "lang" => "eng", "text" => "rare decision" } ] } ],
          "jlpt_waller" => nil }
      ]
    })
    write_source("frequency-web.json", {
      "metadata" => {},
      "entries" => [
        { "text" => "決める", "reading" => "きめる", "rank" => 5, "count" => 100 },
        { "text" => "火曜日", "reading" => "かようび", "rank" => 50, "count" => 80 },
        { "text" => "決稀", "reading" => "けっき", "rank" => 60, "count" => 30 }
      ]
    })
  end

  def write_source(filename, data)
    sources_dir.join(filename).write(JSON.generate(data))
  end

  def tsv_lines(filename)
    output_dir.join(filename).readlines(chomp: true).drop(1).map { |l| l.split("\t") }
  end

  describe "#convert!" do
    it "returns per-file row counts" do
      expect(converter.convert!).to eq(radicals: 2, kanji: 3, words: 3)
    end

    it "writes radicals keyed by character with a name fallback" do
      converter.convert!
      rows = tsv_lines("radicals.tsv")
      expect(rows).to eq([ [ "水", "85", "water", "4" ], [ "夊", "35", "夊", "3" ] ])
    end

    it "scopes kanji to the top frequency ranks and includes the radical glyph" do
      converter.convert!
      rows = tsv_lines("kanji.tsv")
      expect(rows.size).to eq(3)
      expect(rows.first[0]).to eq("決")
      expect(rows.first[-1]).to eq("水")
    end

    it "includes kanji used by the word bank within the difficulty budget" do
      converter.convert!
      rows = tsv_lines("kanji.tsv")
      fire = rows.find { |r| r[0] == "火" }
      expect(fire).not_to be_nil
      expect(fire[2]).to eq("574")
      expect(fire[5]).to include("カ")
      expect(fire[6]).to include("ひ")
    end

    it "keeps rare kanji beyond the difficulty budget out of the bank" do
      converter.convert!
      rows = tsv_lines("kanji.tsv")
      expect(rows.find { |r| r[0] == "稀" }).to be_nil
    end

    it "scopes words to those containing in-scope kanji with a frequency rank" do
      converter.convert!
      rows = tsv_lines("words.tsv")
      expect(rows.size).to eq(3)
      expect(rows.first).to eq([ "決める", "きめる", "to decide", "5", "N5", "v1" ])
      expect(rows.map { |r| r[0] }).to include("決稀")
    end

    it "raises a helpful error when source files are missing" do
      sources_dir.join("kanji.json").delete
      expect { converter.convert! }.to raise_error(/Missing source file/)
    end
  end
end
