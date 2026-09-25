require "rails_helper"

RSpec.describe "Progress page", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }

  it "lists readable kanji and words" do
    UserKanji.create!(user:, kanji: k["決"], mastery_score: 0.9,
                      recognition_strength: 0.9, reading_strength: 0.9, context_strength: 0.9)
    UserWord.create!(user:, word: w["決める"], mastery_score: 0.8)

    get progress_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Characters you can read")
    expect(response.body).to include("決")
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
end
