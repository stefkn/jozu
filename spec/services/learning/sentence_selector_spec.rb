require "rails_helper"

RSpec.describe Learning::SentenceSelector do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  it "selects a sentence that contains the target kanji" do
    sentence = described_class.new.select(user, kanji: k["決"])
    expect(sentence).not_to be_nil
    expect(sentence.japanese).to include("決")
  end

  it "prefers sentences whose other kanji are frequent or known" do
    sentence = described_class.new.select(user, kanji: k["決"])
    other = sentence.japanese.chars.select { |c| c.ord.between?(0x4e00, 0x9fff) }.reject { |c| c == "決" }
    other.each do |char|
      kanji = Kanji.find_by(character: char)
      next if kanji.nil?
      expect(kanji.frequency_rank).to be <= 2000
    end
  end

  it "avoids sentences recently shown for the target kanji" do
    sentence = described_class.new.select(user, kanji: k["決"])
    Learning::ExposureRecorder.record!(user:, kanji: k["決"], sentence:, kind: "sentence")

    other = described_class.new.select(user, kanji: k["決"])
    if other
      expect(other.id).not_to eq(sentence.id)
    end
  end

  it "returns nil when every candidate fails the difficulty gate" do
    Kanji.update_all(frequency_rank: 9000)
    expect(described_class.new.select(user, kanji: k["決"])).to be_nil
  end
end
