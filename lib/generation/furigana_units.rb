module Generation
  # Converts an LLM-produced { surface => reading } furigana map into position
  # units for a sentence, so Learning::Furigana can render context-correct ruby
  # (plan §8.4: the target kanji is the difficult part; everything else is read).
  #
  # Units are stored on sentences.furigana as [{ "start" => int, "end" => int,
  # "reading" => String }]; positions are character indices into the sentence.
  class FuriganaUnits
    KANJI_RE = /[一-龯]/
    READING_RE = /\A[\p{Hiragana}\p{Katakana}ー]+\z/

    # @return [Array<Hash>]
    def self.call(japanese, furigana_map)
      new(japanese, furigana_map).call
    end

    # Character indices of every kanji in +japanese+.
    def self.kanji_positions(japanese)
      chars = japanese.to_s.chars
      chars.each_index.select { |i| chars[i].match?(KANJI_RE) }
    end

    # True when +units+ cover every kanji position in +japanese+.
    def self.covers?(japanese, units)
      covered = units.flat_map { |u| (u["start"].to_i..u["end"].to_i).to_a }
      (kanji_positions(japanese) - covered).empty?
    end

    def initialize(japanese, furigana_map)
      @chars = japanese.chars
      @furigana = furigana_map.is_a?(Hash) ? furigana_map : {}
    end

    def call
      units = @furigana.filter_map do |surface, reading|
        next unless surface.is_a?(String) && reading.is_a?(String)
        next if surface.blank? || reading.blank?
        next unless surface.match?(KANJI_RE)
        next unless reading.match?(READING_RE)

        span = locate(surface)
        next if span.nil?

        { "start" => span[0], "end" => span[1], "reading" => reading.strip }
      end
      reject_overlaps(units)
    end

    private

    def locate(surface)
      chars = surface.chars
      @chars.each_index do |i|
        return [ i, i + chars.size - 1 ] if @chars[i, chars.size] == chars
      end
      nil
    end

    def reject_overlaps(units)
      units.sort_by { |u| -((u["end"] - u["start"])) }.each_with_object([]) do |unit, picked|
        st, en = unit["start"], unit["end"]
        next if picked.any? { |p| !(p["end"] < st || p["start"] > en) }

        picked << unit
      end.sort_by { |u| u["start"] }
    end
  end
end
