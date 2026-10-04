require "rails_helper"

RSpec.describe "Knownness", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }
  let(:word) { Word.find_by(surface: "決める") }

  it "marks a word as spoken-known via JSON" do
    post knownness_index_path, params: { word_id: word.id, level: "say" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["ok"]).to be true
    expect(UserWord.find_by(user:, word:).mastery_score).to eq(1.0)
  end

  it "rejects unknown levels" do
    post knownness_index_path, params: { word_id: word.id, level: "fluent" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "404s for unknown words" do
    post knownness_index_path, params: { word_id: -1, level: "say" }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
