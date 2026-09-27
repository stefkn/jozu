module Learning
  # Confusion-network substrate, first slice (tech plan §"Learning-loop review
  # 2026-09-25", item 1; concept §10).
  #
  # Mines (correct_option_id, answer_id) pairs from wrong reviews. Rows written
  # before answer tracking (nil answer_id) are ignored. Both ids are stored as
  # strings; for the four multiple-choice types they are kanji/word ids, so a
  # pair directly names the confused characters or words.
  class ConfusionPairs
    Pair = Data.define(:question_type, :target_id, :chosen_id, :count)

    def self.pairs_for(user, question_type: nil, min_count: Learning.config.confusion_min_count, limit: 10)
      new.pairs_for(user, question_type:, min_count:, limit:)
    end

    def self.confusers_for(user, question_type:, target_id:, limit: 3,
                           min_count: Learning.config.confusion_min_count)
      new.confusers_for(user, question_type:, target_id:, limit:, min_count:)
    end

    # The top confuser for a target once the pair has spiked past the contrast
    # threshold, else nil. Used to trigger a focused 2-option contrast drill.
    def self.spike_for(user, question_type:, target_id:,
                       threshold: Learning.config.confusion_contrast_threshold)
      new.spike_for(user, question_type:, target_id:, threshold:)
    end

    # Most-confused (target, chosen) pairs, most frequent first.
    def pairs_for(user, question_type: nil, min_count: Learning.config.confusion_min_count, limit: 10)
      scope = Review.where(user:, correct: false)
                    .where.not(answer_id: [ nil, "" ])
                    .where.not(correct_option_id: [ nil, "" ])
                    .where.not("reviews.answer_id = reviews.correct_option_id")
      scope = scope.where(question_type:) if question_type

      scope.group(:question_type, :correct_option_id, :answer_id)
           .order(Arel.sql("COUNT(*) DESC"))
           .limit(limit)
           .count
           .filter_map do |(type, target_id, chosen_id), count|
             next if count < min_count

             Pair.new(question_type: type, target_id:, chosen_id:, count:)
           end
    end

    # Option ids this user has wrongly chosen for the given target, most
    # frequent first. Used by DistractorSelector to surface deliberate
    # contrast instead of a random plausible option.
    def confusers_for(user, question_type:, target_id:, limit: 3,
                      min_count: Learning.config.confusion_min_count)
      pairs_for(user, question_type:, min_count:, limit:)
        .select { |pair| pair.target_id.to_s == target_id.to_s }
        .map(&:chosen_id)
    end

    def spike_for(user, question_type:, target_id:,
                  threshold: Learning.config.confusion_contrast_threshold)
      confusers_for(user, question_type:, target_id:, limit: 1, min_count: threshold).first
    end
  end
end
