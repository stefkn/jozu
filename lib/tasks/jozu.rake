namespace :jozu do
  desc "Build reference TSVs from vendored sources (plan §4.5); run fetch script first"
  task convert_reference: :environment do
    counts = Imports::ReferenceConverter.new.convert!
    puts "Wrote radicals.tsv (#{counts[:radicals]}), kanji.tsv (#{counts[:kanji]}), words.tsv (#{counts[:words]})."
  end

  desc "Import reference data + generated sentences from vendor/data (plan §4)"
  task import: :environment do
    importer = Imports::CorpusImporter.new
    data_dir = Rails.root.join("vendor/data")

    radicals_path = data_dir.join("radicals.tsv")
    if radicals_path.exist?
      radical_rows = File.readlines(radicals_path, chomp: true).drop(1).filter_map do |line|
        cols = line.split("\t")
        next if cols.size < 3

        { character: cols[0], number: cols[1].presence&.to_i, name: cols[2], stroke_count: cols[3].presence&.to_i }
      end
      puts "Importing #{radical_rows.size} radicals..."
      puts "radicals: #{importer.import_radicals!(radical_rows)}"
    else
      puts "No vendor/data/radicals.tsv found; skipping radical import."
    end

    kanji_path = data_dir.join("kanji.tsv")
    if kanji_path.exist?
      kanji_rows = File.readlines(kanji_path, chomp: true).drop(1).filter_map do |line|
        cols = line.split("\t")
        next if cols.size < 6

        { character: cols[0], grade: cols[1].presence&.to_i, frequency_rank: cols[2].to_i,
          stroke_count: cols[3].presence&.to_i, meaning: cols[4], onyomi: cols[5].to_s.split(","),
          kunyomi: cols[6].to_s.split(","), radical: cols[7].presence }
      end
      puts "Importing #{kanji_rows.size} kanji..."
      puts "kanji: #{importer.import_kanji!(kanji_rows)}"
    else
      puts "No vendor/data/kanji.tsv found; skipping kanji import."
    end

    words_path = data_dir.join("words.tsv")
    if words_path.exist?
      word_rows = File.readlines(words_path, chomp: true).drop(1).filter_map do |line|
        cols = line.split("\t")
        next if cols.size < 5

        { surface: cols[0], reading: cols[1], meaning: cols[2], frequency_rank: cols[3].to_i,
          jlpt_level: cols[4].presence, part_of_speech: cols[5].presence }
      end
      puts "Importing #{word_rows.size} words..."
      puts "words: #{importer.import_words!(word_rows)}"
    else
      puts "No vendor/data/words.tsv found; skipping word import."
    end

    sentences_path = data_dir.join("generated_sentences.natural.jsonl")
    sentences_path = data_dir.join("generated_sentences.jsonl") unless sentences_path.exist?
    if sentences_path.exist?
      sentence_rows = File.readlines(sentences_path, chomp: true).filter_map do |line|
        row = JSON.parse(line)
        next if row["ja"].blank?
        next if (target_word = Word.find_by(surface: row["word"])).nil?

        { japanese: row["ja"], translation: row["en"], source: "llm",
          external_id: Digest::SHA256.hexdigest("#{row['word']}\u0000#{row['kanji']}\u0000#{row['ja']}\u0000#{row['en']}"),
          generation_version: "#{row['model']} #{row['prompt_version']} #{row['seed']}",
          target_word: }
      end
      puts "Importing #{sentence_rows.size} sentences (from #{File.basename(sentences_path)})..."
      stats = importer.import_sentences!(sentence_rows)
      puts "sentences: #{stats[:imported]} imported, #{stats[:rejected]} rejected"
    else
      puts "No vendor/data/generated_sentences.jsonl found; skipping sentence import."
    end
  end

  desc "Rate generated sentences 1–5 into generated_sentences.natural.jsonl (plan §4.3 gate 4)"
  task rate_sentences: :environment do
    input = Rails.root.join("vendor/data/generated_sentences.jsonl")
    output = Rails.root.join("vendor/data/generated_sentences.natural.jsonl")
    concurrency = ENV["JOZU_CONCURRENCY"]&.to_i || 1
    abort "No #{input} found; run jozu:generate_sentences first." unless input.exist?

    external_id_for = ->(row) { Digest::SHA256.hexdigest("#{row['word']}\u0000#{row['kanji']}\u0000#{row['ja']}\u0000#{row['en']}") }
    already = {}
    output.readlines(chomp: true).each { |l| already[external_id_for.call(JSON.parse(l))] = true } if output.exist?

    pending = File.readlines(input, chomp: true).filter_map do |line|
      row = JSON.parse(line)
      next if row["ja"].blank? || already[external_id_for.call(row)]

      row
    end

    queue = Queue.new
    pending.each { |row| queue << row }
    mutex = Mutex.new
    kept = 0
    dropped = 0
    workers = [ concurrency, 1 ].max.times.map do
      Thread.new do
        naturalness = Generation::Naturalness.new
        local_kept = 0
        local_dropped = 0
        loop do
          row = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          break if row.nil?

          score = naturalness.rate(row["ja"])
          if score && score >= Generation::Naturalness::KEEP_SCORE
            output.dirname.mkpath
            mutex.synchronize do
              File.open(output, "a") { |f| f.puts(JSON.generate(row.merge("naturalness" => score))) }
            end
            local_kept += 1
          else
            local_dropped += 1
          end
        end
        mutex.synchronize do
          kept += local_kept
          dropped += local_dropped
        end
      end
    end
    workers.each(&:join)
    puts "Rated #{pending.size}: #{kept} kept, #{dropped} dropped."
  end

  desc "Batch-generate sentences via LLM into vendor/data/generated_sentences.jsonl (plan §4.2)"
  task generate_sentences: :environment do
    limit = ENV["LIMIT"]&.to_i
    concurrency = ENV["JOZU_CONCURRENCY"]&.to_i || 1
    count = Generation::SentenceGenerator.new(concurrency:).run!(limit:)
    puts "Appended #{count} generated sentence rows."
  end

  desc "Print session/review counts for sanity checks (plan §13)"
  task stats: :environment do
    puts "kanji:      #{Kanji.count}"
    puts "words:      #{Word.count}"
    puts "sentences:  #{Sentence.count}"
    puts "sentence_words: #{SentenceWord.count}"
    puts "reviews:    #{Review.count}"
    puts "users:      #{User.count}"
    today = Review.where(created_at: Time.current.all_day)
    puts "reviews today: #{today.count} (#{today.where(correct: true).count} correct)"
  end

  desc "Generate context-correct furigana via LLM into vendor/data/generated_furigana.jsonl"
  task generate_furigana: :environment do
    limit = ENV["LIMIT"]&.to_i
    concurrency = ENV["JOZU_CONCURRENCY"]&.to_i || 1
    count = Generation::FuriganaGenerator.new(concurrency:).run!(limit:)
    puts "Appended #{count} furigana rows."
  end

  desc "Import generated furigana into sentences.furigana"
  task import_furigana: :environment do
    input = Rails.root.join("vendor/data/generated_furigana.jsonl")
    abort "No #{input} found; run jozu:generate_furigana first." unless input.exist?

    # Rows written by the current generator store position-based units; legacy
    # rows store { surface => reading } maps. Normalise both to units.
    normalize = lambda do |row|
      value = row["furigana"]
      return value if value.is_a?(Array)

      Generation::FuriganaUnits.call(row["japanese"].to_s, value)
    end

    updated = 0
    missing = 0
    incomplete = 0
    File.readlines(input, chomp: true).each do |line|
      row = JSON.parse(line)
      sentence = Sentence.find_by(japanese: row["japanese"])
      if sentence.nil?
        missing += 1
        warn "No sentence found for: #{row['japanese'][0, 20]}..."
        next
      end

      units = normalize.call(row)
      unless Generation::FuriganaUnits.covers?(row["japanese"], units)
        incomplete += 1
        warn "Skipping incomplete furigana for: #{row['japanese'][0, 20]}..."
        next
      end

      sentence.update!(furigana: units)
      updated += 1
    end
    puts "Updated #{updated} sentences, #{missing} missing, #{incomplete} incomplete."
  end

  desc "Audit furigana coverage; LIMIT caps the sample listed"
  task check_furigana: :environment do
    limit = ENV["LIMIT"]&.to_i
    complete = 0
    partial = 0
    uncovered = 0
    rows = []

    Sentence.order(:id).find_each do |sentence|
      jp = sentence.japanese
      next if jp.blank?

      kanji_pos = Generation::FuriganaUnits.kanji_positions(jp)
      next if kanji_pos.empty?

      units = sentence.furigana || []
      covered = units.flat_map { |u| (u["start"].to_i..u["end"].to_i).to_a }
      missing = kanji_pos - covered
      if missing.empty?
        complete += 1
        next
      end

      partial += 1
      uncovered += missing.size
      missing_chars = missing.map { |i| jp.chars[i] }.uniq.join
      target = Kanji.find_by(character: missing_chars[0]) || Kanji.first
      rendered = begin
        Learning::Furigana.new(sentence, target).render(jp)
      rescue StandardError
        nil
      end
      rows << { japanese: jp, translation: sentence.translation, missing: missing_chars, rendered: }
    end

    puts "sentences with kanji: #{complete + partial}"
    puts "complete coverage:    #{complete}"
    puts "partial coverage:     #{partial} (#{uncovered} uncovered kanji)"
    puts
    if rows.empty?
      puts "All sentences fully covered."
    else
      sample = limit ? rows.first(limit) : rows.first(20)
      sample.each do |r|
        puts "─ #{r[:japanese]}  (#{r[:translation]})"
        puts "  missing: #{r[:missing]}"
        puts "  renders: #{r[:rendered]}" if r[:rendered]
      end
      puts
      puts "#{rows.size} sentences need attention#{sample.size < rows.size ? " (showing #{sample.size})" : ""}."
    end
  end

  desc "Generate context-aware English kanji definitions via LLM into vendor/data/generated_kanji_meanings.jsonl"
  task generate_kanji_meanings: :environment do
    limit = ENV["LIMIT"]&.to_i
    concurrency = ENV["JOZU_CONCURRENCY"]&.to_i || 1
    count = Generation::KanjiMeaningGenerator.new(concurrency:).run!(limit:)
    puts "Appended #{count} kanji-meaning rows."
  end

  desc "Import generated kanji definitions into sentences.kanji_meanings"
  task import_kanji_meanings: :environment do
    input = Rails.root.join("vendor/data/generated_kanji_meanings.jsonl")
    abort "No #{input} found; run jozu:generate_kanji_meanings first." unless input.exist?

    updated = 0
    missing = 0
    File.readlines(input, chomp: true).each do |line|
      row = JSON.parse(line)
      sentence = Sentence.find_by(japanese: row["japanese"])
      if sentence.nil?
        missing += 1
        warn "No sentence found for: #{row['japanese'][0, 20]}..."
        next
      end

      units = Generation::KanjiMeaningUnits.call(row["japanese"], row["meanings"], sentence.furigana)
      sentence.update!(kanji_meanings: units)
      updated += 1
    end
    puts "Updated #{updated} sentences, #{missing} missing."
  end
end
