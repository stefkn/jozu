module Segmentation
  # Deterministic left-to-right word segmentation using a prefix trie of word
  # surfaces (plan §4.4). At each position the longest matching surface wins;
  # unmatchable characters are skipped. This is an approximation for Plan A —
  # Sudachi/mecab replaces it in Plan B behind the same `sentence_words` table.
  class LongestMatch
    Token = Data.define(:surface, :start_position, :end_position)

    def self.build(surfaces)
      new(surfaces)
    end

    def initialize(surfaces)
      @root = {}
      surfaces.each { |surface| insert(surface) }
    end

    # @return [Array<Token>] matched tokens in reading order.
    def segment(text)
      tokens = []
      i = 0
      length = text.length

      while i < length
        match = longest_match_from(text, i)
        if match
          surface = text[i, match]
          tokens << Token.new(surface:, start_position: i, end_position: i + match - 1)
          i += match
        else
          i += 1
        end
      end

      tokens
    end

    private

    def insert(surface)
      node = @root
      surface.each_char do |char|
        node = (node[char] ||= {})
      end
      node[:_end] = true
    end

    def longest_match_from(text, start)
      node = @root
      longest = nil
      index = start

      while index < text.length
        node = node[text[index]]
        break unless node

        longest = index - start + 1 if node[:_end]
        index += 1
      end

      longest
    end
  end
end
