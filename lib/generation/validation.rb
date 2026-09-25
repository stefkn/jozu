module Generation
  # Validation gates applied at import (plan §4.3). Guarantees the "target kanji is
  # the difficult part" property and keeps the sentence bank reviewable.
  class Validation
    Result = Data.define(:valid, :reasons)

    SENTENCE_PUNCTUATION = /[。！？]$/
    TARGET_OTHER_KANJI_MAX_RANK = 2000

    def self.validate(sentence:, target_word:, en:, segmenter:, max_other_kanji_rank: TARGET_OTHER_KANJI_MAX_RANK, kanji_ranks: nil)
      new.validate(sentence:, target_word:, en:, segmenter:, max_other_kanji_rank:, kanji_ranks:)
    end

    # @return [Result]
    def validate(sentence:, target_word:, en:, segmenter:, max_other_kanji_rank:, kanji_ranks: nil)
      reasons = []
      reasons << "missing translation" if en.to_s.strip.empty?
      reasons << "wrong length (#{sentence.length} chars)" unless sentence.length.between?(6, 30)
      reasons << "missing sentence-final punctuation" unless sentence.match?(SENTENCE_PUNCTUATION)
      reasons << "missing target word" if target_word.nil?
      unless target_word.nil?
        reasons << "target word not found" unless contains_word?(sentence, target_word, segmenter)

        other_kanji = self.class.kanji_chars(sentence).reject { |c| target_word.surface.include?(c) }
        reasons << "other kanji exceed frequency budget" unless kanji_budget_ok?(other_kanji, max_other_kanji_rank, kanji_ranks)
      end

      Result.new(valid: reasons.empty?, reasons:)
    end

    # Jaccard gate on the normalised kanji set (plan §4.3, gate 3).
    def self.duplicate?(sentence_a, sentence_b)
      set_a = kanji_chars(sentence_a).uniq
      set_b = kanji_chars(sentence_b).uniq
      return true if set_a == set_b

      intersection = (set_a & set_b).size
      union = (set_a | set_b).size
      union.positive? && (intersection.to_f / union) > 0.8
    end

    def self.kanji_chars(text)
      text.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }
    end

    private

    def contains_word?(sentence, target_word, segmenter)
      segmenter.segment(sentence).any? { |token| token.surface == target_word.surface }
    end

    def kanji_budget_ok?(kanji_chars, max_rank, kanji_ranks)
      kanji_chars.all? do |char|
        rank = kanji_ranks ? kanji_ranks[char] : Kanji.find_by(character: char)&.frequency_rank
        rank.nil? || rank <= max_rank
      end
    end
  end
end
