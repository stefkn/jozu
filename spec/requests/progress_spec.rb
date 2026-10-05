require "rails_helper"

RSpec.describe "Progress page", type: :request do
  include CorpusHelper

  before { build_corpus!; sign_in(make_user) }

  let(:user) { User.first }

  it "lists readable kanji and words" do
    UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.9,
                      recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)
    UserWord.create!(user:, word: w["決める"], mastery_score: 0.8)

    get progress_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Characters you can read")
    expect(response.body).to include("決")
    expect(response.body).to include("decide")
    expect(response.body).to include("けつ")
    expect(response.body).to include("Words you can read")
    expect(response.body).to include("決める")
    expect(response.body).to include("きめる")
  end

  it "renders empty states" do
    get progress_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing reliably readable yet")
    expect(response.body).to include("No words unlocked yet")
  end

  it "links tiles to kanji study notes with a dialog pane" do
    UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.9,
                      recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)

    get progress_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("kanji-dialog")
    expect(response.body).to include("data-kanji-dialog-target=\"dialog\"")
    expect(response.body).to include(progress_kanji_path("決"))
  end

  it "shows study notes for a kanji" do
    UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.9,
                      recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)

    get progress_kanji_path("決")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Study notes")
    expect(response.body).to include("decide")
    expect(response.body).to include("data-kanji-detail")
    # Common readings with ON/KUN badges, as in review study notes.
    expect(response.body).to include("KUN")
  end

  it "shows study notes for an unseen kanji" do
    get progress_kanji_path("要")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Study notes")
    expect(response.body).to include("need, essential")
    expect(response.body).to include("Not yet seen")
  end

  it "404s for an unknown character" do
    get progress_kanji_path("A")
    expect(response).to have_http_status(:not_found)
  end
end
