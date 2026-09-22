require "rails_helper"

RSpec.describe Learning::ExposureRecorder do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:kanji) { k["決"] }

  describe ".record!" do
    it "records an exposure with a Sentence object" do
      sentence = s["決定は後で連絡します。"]
      described_class.record!(user:, kanji:, sentence:, kind: "sentence")
      expect(Exposure.last.sentence_id).to eq(sentence.id)
    end

    it "records an exposure with a sentence_id (the quiz controller's shape)" do
      sentence = s["決定は後で連絡します。"]
      described_class.record!(user:, kanji:, sentence_id: sentence.id, kind: "sentence")
      expect(Exposure.last.sentence_id).to eq(sentence.id)
    end

    it "records a review exposure with no sentence" do
      described_class.record!(user:, kanji:, kind: "review")
      expect(Exposure.last.sentence_id).to be_nil
      expect(Exposure.last.kind).to eq("review")
    end
  end
end
