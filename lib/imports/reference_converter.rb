module Imports
  # Converts the vendored jkindrix/japanese-language-data JSON files
  # (vendor/data/sources/) into the TSV shapes the importer reads
  # (vendor/data/{radicals,kanji,words}.tsv). Pure data transformation:
  # no ActiveRecord, runnable offline after script/fetch_reference_data.rb.
  #
  # Scopes (plan §4.5):
  #   kanji: top ~500 by KANJIDIC2 frequency rank, PLUS every kanji that appears
  #          in any vocabulary word (all of words.json, not just the emitted
  #          words.tsv) within the app's difficulty budget (rank ≤ 2000 — the
  #          "other kanji" ceiling in Validation / SentenceSelector). This closure
  #          means words AND generated sentences never reference a kanji that
  #          lacks readings/radical/stroke, while rare kanji (> 2000) stay out.
  #   words: common words containing ≥1 in-scope kanji, top ~4,000 by web
  #          frequency rank (frequency-web.json)
  #   radicals: full Kangxi radical set (253)
  class ReferenceConverter
    KANJI_LIMIT = 500
    WORD_LIMIT = 4000
    # Matches Validation::TARGET_OTHER_KANJI_MAX_RANK / SentenceSelector:
    # kanji beyond this frequency are "rare" and kept out of the bank.
    CLOSURE_MAX_RANK = 2000

    def initialize(sources_dir: Rails.root.join("vendor/data/sources"),
                   output_dir: Rails.root.join("vendor/data"))
      @sources_dir = sources_dir
      @output_dir = output_dir
    end

    # @return [Hash<Symbol, Integer>] row counts written per file.
    def convert!
      radicals = load_json("radicals.json")["radicals"]
      kanji = load_json("kanji.json")["kanji"]
      words = load_json("words.json")["words"]
      word_freq = load_json("frequency-web.json")["entries"]

      in_scope = in_scope_kanji(kanji)
      word_rows = build_word_rows(words, word_freq, in_scope)
      kanji_rows = closure_kanji_rows(kanji, in_scope, words)

      radical_count = write_radicals_tsv(radicals)
      kanji_count = write_kanji_tsv(kanji_rows, radicals)
      word_count = write_words_tsv(word_rows)

      { radicals: radical_count, kanji: kanji_count, words: word_count }
    end

    private

    def load_json(filename)
      path = @sources_dir.join(filename)
      raise "Missing source file #{path}. Run script/fetch_reference_data.rb first." unless path.exist?

      JSON.parse(File.read(path))
    end

    # char => true for the top-KANJI_LIMIT kanji by KANJIDIC2 frequency.
    def in_scope_kanji(kanji)
      kanji.each_with_object({}) do |k, set|
        set[k["character"]] = true if k["frequency"].is_a?(Integer) && k["frequency"] <= KANJI_LIMIT
      end
    end

    # Words containing ≥1 in-scope kanji, most frequent first, deduped by surface.
    def build_word_rows(words, word_freq, in_scope)
      freq_by_surface = word_freq.index_by { |e| e["text"] }
      rows = words.filter_map do |entry|
        surface, reading = primary_forms(entry)
        next if surface.nil?
        next unless surface.chars.any? { |c| in_scope.key?(c) }

        rank = freq_by_surface.dig(surface, "rank") || freq_by_surface.dig(reading, "rank")
        next if rank.nil?

        { surface:, reading:, meaning: meaning_for(entry), rank:,
          jlpt: entry["jlpt_waller"], pos: pos_for(entry) }
      end
      rows.group_by { |r| r[:surface] }.values.map { |group| group.min_by { |r| r[:rank] } }
          .sort_by { |r| r[:rank] }.first(WORD_LIMIT)
    end

    # Top-KANJI_LIMIT rows plus every kanji used by any vocabulary word that is
    # within the difficulty budget (e.g. 火 in 火曜日, 忘 in 忘れる) — so words
    # and generated sentences always have complete kanji data. Words whose only
    # kanji are beyond the top-KANJI_LIMIT still contribute to the closure, so a
    # rare-but-common-ish kanji used in a sentence is banked even if its word
    # never made words.tsv.
    def closure_kanji_rows(kanji, in_scope, words)
      used = words.flat_map { |e| Array(e["kanji"]).map { |k| k["text"] }.join.chars }
                  .select { |c| c.ord.between?(0x4e00, 0x9fff) }
                  .uniq
      by_char = kanji.index_by { |k| k["character"] }

      selected = kanji.select { |k| k["frequency"].is_a?(Integer) && k["frequency"] <= KANJI_LIMIT }
                      .sort_by { |k| k["frequency"] }
      extras = used.reject { |c| in_scope.key?(c) }
                   .filter_map { |c| by_char[c] }
                   .select { |k| k["frequency"].is_a?(Integer) && k["frequency"] <= CLOSURE_MAX_RANK }
      selected + extras
    end

    def write_radicals_tsv(radicals)
      rows = radicals.map do |r|
        name = Array(r["meanings"]).join(", ").presence || r["radical"]
        [ r["radical"], r["classical_number"], name, r["stroke_count"] ]
      end
      write_tsv("radicals.tsv", rows, %w[character number name stroke_count])
      rows.size
    end

    def write_kanji_tsv(kanji_rows, radicals)
      canonical = radicals.each_with_object({}) do |r, map|
        number = r["classical_number"]
        next if number.nil?

        current = map[number]
        map[number] = r if current.nil? || r["kanji"].size > current["kanji"].size
      end

      rows = kanji_rows.map do |k|
        radical = canonical[k.dig("radical", "classical")]

        [ k["character"], k["grade"], k["frequency"], k["stroke_count"],
          Array(k.dig("meanings", "en")).join(", "),
          Array(k.dig("readings", "on")).join(","),
          Array(k.dig("readings", "kun")).join(","),
          radical&.[]("radical") ]
      end
      write_tsv("kanji.tsv", rows, %w[character grade frequency_rank stroke_count meaning onyomi kunyomi radical])
      rows.size
    end

    def write_words_tsv(word_rows)
      write_tsv("words.tsv", word_rows.map { |r| r.values_at(:surface, :reading, :meaning, :rank, :jlpt, :pos) },
                %w[surface reading meaning frequency_rank jlpt_level part_of_speech])
      word_rows.size
    end

    def primary_forms(entry)
      surface = entry["kanji"].find { |k| k["common"] }&.[]("text")
      reading = entry["kana"].find { |k| k["common"] }&.[]("text")
      # Fall back to the kana form when the word has no kanji writing; guard
      # against entries whose kana forms are all uncommon.
      surface ||= reading
      reading ||= surface
      [ surface, reading ]
    end

    def meaning_for(entry)
      glosses = entry["sense"].take(2).flat_map { |s| s["gloss"] }
                             .filter_map { |g| g["text"] if g["lang"] == "eng" }
      glosses.uniq.join("; ")
    end

    def pos_for(entry)
      entry.dig("sense", 0, "partOfSpeech", 0)
    end

    def write_tsv(filename, rows, headers)
      @output_dir.mkpath
      File.open(@output_dir.join(filename), "w") do |f|
        f.puts(headers.join("\t"))
        rows.each { |row| f.puts(row.map { |cell| cell.nil? ? "" : cell }.join("\t")) }
      end
    end
  end
end
