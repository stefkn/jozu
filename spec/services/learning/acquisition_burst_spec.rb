require "rails_helper"

RSpec.describe Learning::AcquisitionBurst do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  it "returns no pending items when nothing is started" do
    expect(described_class.pending(user)).to be_empty
  end

  it "tracks a fresh answer as burst-pending with kana then sentence follow-ups" do
    uk = UserKanji.create!(user:, kanji: k["決"], times_seen: 1, last_seen_at: Time.current)

    pending = described_class.pending(user)
    expect(pending.map(&:id)).to eq([ uk.id ])
    expect(described_class.burst_type(1)).to eq("kana_to_kanji")
    expect(described_class.burst_type(2)).to eq("sentence_to_kanji")
    expect(described_class.burst_type(3)).to be_nil
  end

  it "completes the burst once times_seen reaches the burst size" do
    UserKanji.create!(user:, kanji: k["決"], times_seen: 3, last_seen_at: Time.current)
    expect(described_class.pending(user)).to be_empty
  end

  it "excludes graduated, suspended and skipped items" do
    now = Time.current
    good = UserKanji.create!(user:, kanji: k["決"], times_seen: 1, last_seen_at: now)
    UserKanji.create!(user:, kanji: k["定"], times_seen: 1, last_seen_at: now, graduated_at: now)
    UserKanji.create!(user:, kanji: k["必"], times_seen: 1, last_seen_at: now, suspended_at: now)

    expect(described_class.pending(user).map(&:id)).to eq([ good.id ])
  end
end
