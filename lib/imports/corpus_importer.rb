module Imports
  # Generic idempotent, batched importer (plan §4.5). Each method upserts rows by
  # their natural key and wraps work in transactions.
  class CorpusImporter
    BATCH_SIZE = 500

    # rows: [{ character:, grade:, frequency_rank:, stroke_count:, meaning:,
    #          onyomi: [], kunyomi: [] }]
    def import_kanji!(rows)
      rows.each_slice(BATCH_SIZE) do |batch|
        ActiveRecord::Base.transaction do
          batch.each do |row|
            kanji = Kanji.find_or_initialize_by(character: row[:character])
            kanji.update!(
              grade: row[:grade],
              frequency_rank: row[:frequency_rank],
              stroke_count: row[:stroke_count],
              meaning_summary: row[:meaning]
            )
            insert_readings(kanji, row[:onyomi] || [], "onyomi")
            insert_readings(kanji, row[:kunyomi] || [], "kunyomi")
          end
        end
      end
      Kanji.count
    end

    # rows: [{ surface:, reading:, meaning:, frequency_rank:, jlpt_level:, part_of_speech: }]
    def import_words!(rows)
      rows.each_slice(BATCH_SIZE) do |batch|
        ActiveRecord::Base.transaction do
          batch.each do |row|
            word = Word.find_or_initialize_by(surface: row[:surface])
            word.update!(
              reading: row[:reading],
              meaning: row[:meaning],
              frequency_rank: row[:frequency_rank],
              jlpt_level: row[:jlpt_level],
              part_of_speech: row[:part_of_speech]
            )
            link_kanji(word)
          end
        end
      end
      Word.count
    end

    # rows: [{ japanese:, translation:, source:, external_id:, generation_version:, difficulty: }]
    # Sentences are validated and segmented before insert.
    def import_sentences!(rows, importer: nil, validator: Generation::Validation)
      segmenter = Segmentation::LongestMatch.build(Word.pluck(:surface))
      stats = { imported: 0, rejected: 0 }
      rows.each_slice(BATCH_SIZE) do |batch|
        ActiveRecord::Base.transaction do
          batch.each do |row|
            result = validator.validate(
              sentence: row[:japanese],
              target_word: row[:target_word],
              en: row[:translation],
              segmenter:
            )
            unless result.valid
              stats[:rejected] += 1
              warn "Rejected sentence #{row[:external_id]}: #{result.reasons.join(', ')}"
              next
            end

            sentence = Sentence.find_or_initialize_by(external_id: row[:external_id])
            sentence.update!(
              japanese: row[:japanese],
              translation: row[:translation],
              difficulty: row[:difficulty] || estimate_difficulty(row[:japanese]),
              source: row[:source],
              generation_version: row[:generation_version]
            )
            segment_sentence(sentence, segmenter)
            stats[:imported] += 1
          end
        end
      end
      stats
    end

    private

    def insert_readings(kanji, readings, kind)
      readings.each do |reading|
        kanji.readings.find_or_initialize_by(reading:, kind:).save!
      end
    end

    def link_kanji(word)
      word.surface.chars.each_with_index do |char, index|
        next unless char.ord.between?(0x4e00, 0x9fff)

        kanji = Kanji.find_by(character: char)
        next if kanji.nil?

        WordKanji.find_or_initialize_by(word:, kanji:).update!(position: index)
      end
    end

    def segment_sentence(sentence, segmenter)
      segmenter.segment(sentence.japanese).each do |token|
        word = Word.find_by(surface: token.surface)
        next if word.nil?

        SentenceWord.find_or_initialize_by(sentence:, word:).update!(
          start_position: token.start_position,
          end_position: token.end_position
        )
      end
    end

    # Baseline difficulty from the kanji frequency profile (plan §8.4).
    def estimate_difficulty(japanese)
      ranks = Generation::Validation.kanji_chars(japanese).filter_map do |char|
        Kanji.find_by(character: char)&.frequency_rank
      end
      return 3 if ranks.empty?

      mean = ranks.sum.to_f / ranks.size
      case mean
      when 0...100 then 1
      when 100...300 then 2
      when 300...800 then 3
      when 800...1500 then 4
      else 5
      end
    end
  end
end
