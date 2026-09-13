require "rails_helper"

RSpec.describe "Diagnostic flow", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  it "walks through the diagnostic flashcards and seeds user state" do
    Learning.config.diagnostic_question_count = 3

    get diagnostic_path
    expect(response).to have_http_status(:ok)

    3.times do
      token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
      expect(token).not_to be_nil

      post answer_diagnostic_path, params: {
        question_token: token,
        knew: "knew"
      }, as: :turbo_stream
    end

    expect(response.body).to include("Diagnostic complete")
    expect(UserKanji.count).to be >= 1
    expect(UserWord.count).to be >= 1
    expect(Review.where(question_type: "kanji_recognition").count).to be >= 1
  end

  it "shows a diagnostic CTA on home for a fresh user" do
    get root_path
    expect(response.body).to include("Take the diagnostic")
  end

it "shows Start instead of the diagnostic once user state exists" do
      UserKanji.create!(user: User.first, kanji: Kanji.first)
      get root_path
      expect(response.body).to include("Start")
      expect(response.body).not_to include("Take the diagnostic")
    end
end
