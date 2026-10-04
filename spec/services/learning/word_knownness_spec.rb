require "rails_helper"

RSpec.describe Learning::WordKnownness do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }

  it "creates a UserWord with the mapped mastery for 'say'" do
    record = described_class.mark!(user, word: w["決める"], level: "say", now:)
    expect(record.mastery_score).to eq(1.0)
    expect(record.first_seen_at).not_to be_nil
  end

  it "updates an existing row without touching SRS state" do
    existing = UserWord.create!(user:, word: w["決める"], mastery_score: 0.2)
    record = described_class.mark!(user, word: w["決める"], level: "known", now:)
    expect(record.id).to eq(existing.id)
    expect(record.mastery_score).to eq(0.6)
    expect(record.srs_state).to eq(existing.srs_state)
  end

  it "maps unknown to a low prior" do
    record = described_class.mark!(user, word: w["決める"], level: "unknown", now:)
    expect(record.mastery_score).to be < 0.6
  end

  it "rejects unknown levels" do
    expect { described_class.mark!(user, word: w["決める"], level: "fluent", now:) }
      .to raise_error(ArgumentError)
  end

  it "feeds leverage immediately" do
    described_class.mark!(user, word: w["決める"], level: "say", now:)
    weight = Learning::LeverageCalculator.new.word_weight(w["決める"], user)
    expect(weight).to eq(1.0)
  end
end
