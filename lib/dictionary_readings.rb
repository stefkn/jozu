module DictionaryReadings
  KANJI_RE = /[一-龯]/

  module_function

  # Longest, non-overlapping words from the words table for kanji positions not
  # covered by +covered+ (character indices into +japanese+). Used to repair
  # coverage gaps left by the LLM furigana pass (it systematically skips single
  # kanji verbs with okurigana like 行き/大きい) and by the runtime renderer, so
  # 好き -> すき is read as a word instead of decomposed into 好's primary
  # reading (このむ).
  #
  # @return [Array<[Integer, Integer, String]>] (start, end, reading) spans.
  def fill(japanese, covered:)
    chars = japanese.to_s.chars
    length = chars.size
    positions = chars.each_index.select { |i| kanji?(chars[i]) && !covered.include?(i) }
    return [] if positions.empty?

    surfaces = {}
    positions.each do |i|
      j = i
      while j < length && !covered.include?(j)
        surfaces[chars[i..j].join] = true
        j += 1
      end
    end
    return [] if surfaces.empty?

    by_surface = Word.where(surface: surfaces.keys)
                     .where.not(reading: [ nil, "" ])
                     .order(:frequency_rank)
                     .group_by(&:surface)

    candidates = []
    positions.each do |i|
      j = i
      while j < length && !covered.include?(j)
        word = by_surface[chars[i..j].join]&.first
        candidates << [ i, j, word.reading.to_s ] if word
        j += 1
      end
    end
    return [] if candidates.empty?

    candidates.sort_by! { |(st, en, _)| -(en - st) }
    picked = []
    candidates.each do |(st, en, rd)|
      next if picked.any? { |(pst, pen, _)| !(pen < st || pst > en) }

      picked << [ st, en, rd ]
    end
    picked.sort_by! { |(st, _, _)| st }
  end

  def kanji?(char)
    char.ord.between?(0x4e00, 0x9fff)
  end
end
