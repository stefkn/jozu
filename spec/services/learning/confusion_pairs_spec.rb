require "rails_helper"

RSpec.describe Learning::ConfusionPairs do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:other_user) { create(:user) }

  def wrong_review(user:, type:, correct_id:, chosen_id:)
    uk = UserKanji.find_or_create_by!(user:, kanji: k["決"])
    Review.create!(
      user:, reviewable: uk, question_type: type, grade: "again",
      distractors: [ chosen_id ], answer_id: chosen_id.to_s,
      correct_option_id: correct_id.to_s,
      presented_at: Time.current, answered_at: Time.current, correct: false
    )
  end

  describe ".pairs_for" do
    it "returns (target, chosen) pairs ordered by frequency" do
      twice = k["決"].id
      once_target = k["定"].id
      wrong_review(user:, type: "sentence_to_kanji", correct_id: twice, chosen_id: k["持"].id)
      wrong_review(user:, type: "sentence_to_kanji", correct_id: twice, chosen_id: k["持"].id)
      wrong_review(user:, type: "sentence_to_kanji", correct_id: once_target, chosen_id: k["必"].id)

      pairs = described_class.pairs_for(user)
      expect(pairs.map(&:count)).to eq([ 2, 1 ])
      expect(pairs.first.target_id.to_s).to eq(twice.to_s)
      expect(pairs.first.chosen_id.to_s).to eq(k["持"].id.to_s)
    end

    it "ignores correct answers, pre-tracking rows, and self-answers" do
      uk = UserKanji.create!(user:, kanji: k["決"])
      Review.create!(user:, reviewable: uk, question_type: "kana_to_kanji", grade: "good",
                     presented_at: Time.current, answered_at: Time.current, correct: true,
                     answer_id: k["決"].id.to_s, correct_option_id: k["決"].id.to_s)
      Review.create!(user:, reviewable: uk, question_type: "kana_to_kanji", grade: "again",
                     presented_at: Time.current, answered_at: Time.current, correct: false)

      expect(described_class.pairs_for(user)).to be_empty
    end

    it "scopes to the user and optionally the question type" do
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      wrong_review(user: other_user, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      wrong_review(user:, type: "kana_to_kanji", correct_id: w["決める"].id, chosen_id: w["持つ"].id)

      expect(described_class.pairs_for(user).size).to eq(2)
      expect(described_class.pairs_for(user, question_type: "kana_to_kanji").size).to eq(1)
      expect(described_class.pairs_for(other_user).size).to eq(1)
    end

    it "applies min_count" do
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      expect(described_class.pairs_for(user, min_count: 2)).to be_empty
      expect(described_class.pairs_for(user, min_count: 1).size).to eq(1)
    end
  end

  describe ".confusers_for" do
    it "returns chosen ids for the target, most frequent first" do
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["待"].id)

      expect(described_class.confusers_for(user, question_type: "sentence_to_kanji", target_id: k["決"].id))
        .to eq([ k["持"].id.to_s, k["待"].id.to_s ])
      expect(described_class.confusers_for(user, question_type: "sentence_to_kanji", target_id: k["定"].id))
        .to be_empty
    end
  end

  describe ".spike_for" do
    it "returns the top confuser once the pair reaches the threshold" do
      expect(described_class.spike_for(user, question_type: "sentence_to_kanji", target_id: k["決"].id))
        .to be_nil

      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      expect(described_class.spike_for(user, question_type: "sentence_to_kanji", target_id: k["決"].id))
        .to be_nil

      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      expect(described_class.spike_for(user, question_type: "sentence_to_kanji", target_id: k["決"].id))
        .to eq(k["持"].id.to_s)
    end

    it "respects a custom threshold and question type scope" do
      wrong_review(user:, type: "sentence_to_kanji", correct_id: k["決"].id, chosen_id: k["持"].id)
      expect(described_class.spike_for(user, question_type: "sentence_to_kanji", target_id: k["決"].id,
                                       threshold: 1)).to eq(k["持"].id.to_s)
      expect(described_class.spike_for(user, question_type: "kana_to_kanji", target_id: k["決"].id,
                                       threshold: 1)).to be_nil
    end
  end
end
