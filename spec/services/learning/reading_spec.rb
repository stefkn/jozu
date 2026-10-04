require "rails_helper"

RSpec.describe Learning::ReadingPassage do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }

  it "selects up to the configured sentence count with furigana html" do
    passages = described_class.select(user)
    expect(passages.size).to be <= Learning.config.reading_sentence_count
    expect(passages.size).to be > 0
    expect(passages.first.html).to be_present
    expect(passages.first.sentence).to be_a(Sentence)
  end

  it "is available when unread sentences exist" do
    expect(described_class.available?(user)).to be true
  end

  it "prefers high-comprehension sentences" do
    # Mark every word in one sentence as spoken-known; it should surface first.
    # NOTE: "これは必ず必要です。" links to 必ず/必要 via longest-match, while
    # conjugated forms like 決めます do not link to 決める.
    sentence = s["これは必ず必要です。"]
    expect(sentence.words).not_to be_empty
    sentence.words.each do |word|
      Learning::WordKnownness.mark!(user, word:, level: "say")
    end

    passages = described_class.select(user, count: 3)
    expect(passages.map { |p| p.sentence.id }).to include(sentence.id)
  end
end

RSpec.describe Learning::ReadingFeedback do
  include CorpusHelper

  before { build_corpus! }

  let(:user) { make_user }
  let(:now) { Time.current }

  it "records reading exposures and bumps context without touching SRS" do
    uk = UserKanji.create!(user:, kanji: k["決"], context_strength: 0.1,
                           recognition_strength: 0.5, reading_strength: 0.5, mastery_score: 0.4)
    Learning::Scheduler.new.apply!(uk, grade: :good, now: now - 2.days)
    due_before = uk.due_at
    srs_before = uk.srs_state

    sentence = s["明日までに決めます。"]
    described_class.record!(user:, sentences: [ sentence ], now:)

    expect(Exposure.where(user:, kind: "reading", sentence_id: sentence.id).count).to be >= 1
    uk.reload
    expect(uk.context_strength).to be > 0.1
    expect(uk.srs_state).to eq(srs_before)
    expect(uk.due_at).to eq(due_before)
  end

  it "skips graduated and suspended items for bumps but still records exposures" do
    UserKanji.create!(user:, kanji: k["決"], context_strength: 0.1, graduated_at: now)
    sentence = s["明日までに決めます。"]

    described_class.record!(user:, sentences: [ sentence ], now:)

    expect(Exposure.where(user:, kind: "reading").count).to be > 0
    expect(UserKanji.find_by(user:, kanji: k["決"]).context_strength).to eq(0.1)
  end
end
