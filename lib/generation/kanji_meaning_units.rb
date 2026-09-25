module Generation
  # Converts an LLM-produced { word => meaning } map into position units aligned
  # with the sentence's stored furigana word units, so Learning::Furigana can
  # render tap-to-show English definitions for whole words (東京 -> "Tokyo", not
  # per-character "east"/"capital").
  #
  # Units are stored on sentences.kanji_meanings as [{ "start" => int,
  # "end" => int, "meaning" => String }]; the spans are the furigana unit spans.
  class KanjiMeaningUnits
    ENGLISH_RE = /\A[a-zA-Z][a-zA-Z .,'()\-!]*\z/

    # @param furigana_units [Array<Hash>] the sentence's stored furigana units,
    #   [{ "start" => int, "end" => int, "reading" => String }].
    # @return [Array<Hash>]
    def self.call(japanese, meaning_map, furigana_units)
      new(japanese, meaning_map, furigana_units).call
    end

    def initialize(japanese, meaning_map, furigana_units)
      @japanese = japanese
      @meanings = meaning_map.is_a?(Hash) ? meaning_map : {}
      @units = furigana_units.is_a?(Array) ? furigana_units : []
    end

    def call
      @units.filter_map do |unit|
        start_pos = unit["start"].to_i
        end_pos = unit["end"].to_i
        surface = @japanese[start_pos..end_pos]
        meaning = @meanings[surface]
        next if meaning.blank?

        meaning = meaning.to_s.strip
        next unless meaning.match?(ENGLISH_RE)
        next if meaning.length > 40

        { "start" => start_pos, "end" => end_pos, "meaning" => meaning }
      end
    end
  end
end
