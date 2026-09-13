namespace :jozu do
  desc "Import reference data + generated sentences from vendor/data (plan §4)"
  task import: :environment do
    importer = Imports::CorpusImporter.new
    data_dir = Rails.root.join("vendor/data")

    kanji_path = data_dir.join("kanji.tsv")
    if kanji_path.exist?
      kanji_rows = File.readlines(kanji_path, chomp: true).drop(1).filter_map do |line|
        cols = line.split("\t")
        next if cols.size < 6

        { character: cols[0], grade: cols[1].presence&.to_i, frequency_rank: cols[2].to_i,
          stroke_count: cols[3].presence&.to_i, meaning: cols[4], onyomi: cols[5].to_s.split(",") }
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

    sentences_path = data_dir.join("generated_sentences.jsonl")
    if sentences_path.exist?
      sentence_rows = File.readlines(sentences_path, chomp: true).filter_map do |line|
        row = JSON.parse(line)
        next if row["ja"].blank?

        { japanese: row["ja"], translation: row["en"], source: "llm",
          external_id: Digest::SHA256.hexdigest(line), generation_version: "#{row['model']} #{row['prompt_version']} #{row['seed']}",
          target_word: Word.find_by(surface: row["word"]) }
      end
      puts "Importing #{sentence_rows.size} sentences..."
      stats = importer.import_sentences!(sentence_rows)
      puts "sentences: #{stats[:imported]} imported, #{stats[:rejected]} rejected"
    else
      puts "No vendor/data/generated_sentences.jsonl found; skipping sentence import."
    end
  end

  desc "Batch-generate sentences via LLM into vendor/data/generated_sentences.jsonl (plan §4.2)"
  task generate_sentences: :environment do
    limit = ENV["LIMIT"]&.to_i
    count = Generation::SentenceGenerator.new.run!(limit:)
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
end
