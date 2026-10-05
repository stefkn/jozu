require "rails_helper"

RSpec.describe "Account isolation", type: :request do
  include CorpusHelper

  before do
    Rails.cache.clear
    build_corpus!
  end

  it "isolates preferences, progress and question answers when switching accounts" do
    first = create(:user)
    second = create(:user)
    sign_in(first)
    get next_sessions_path
    token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    question = Learning::QuestionStore.fetch(token, user: first)
    study_item = first.user_kanji.find(question.reviewable_id)
    before_state = study_item.attributes
    sign_in(second)
    patch settings_path, params: { theme: "dark" }, as: :json
    expect(first.reload.theme).to eq("system")
    expect(second.reload.theme).to eq("dark")
    get progress_path
    expect(response).to have_http_status(:ok)
    expect(second.user_kanji).to be_empty
    expect do
      post reviews_path, params: { question_token: token, answer_id: question.correct_option_id, confidence: "knew" }
    end.not_to change(Review, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(study_item.reload.attributes).to eq(before_state)
    expect(Learning::QuestionStore.fetch(token, user: first)).to eq(question)
    expect(Learning::QuestionStore.fetch(token, user: second)).to be_nil
  end

  it "checks ownership even if a question is put in the wrong user's namespace" do
    first = create(:user)
    second = create(:user)
    question = Learning::NextReview.call(first)
    Learning::QuestionStore.put(question, user: second)
    sign_in(second)
    expect do
      post reviews_path, params: { question_token: question.token, answer_id: question.correct_option_id }
    end.not_to change(Review, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(first.user_kanji.first.reload.times_seen).to eq(0)
  end

  it "rejects another user's diagnostic token and a repeated diagnostic answer" do
    first = create(:user)
    second = create(:user)
    flashcard = Learning::Diagnostic.start(first)
    sign_in(second)
    post answer_diagnostic_path, params: { question_token: flashcard.token, knew: "knew" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Learning::Diagnostic.state_for(second).asked).to eq(0)
    sign_in(first)
    post answer_diagnostic_path, params: { question_token: flashcard.token, knew: "knew" }
    expect(Learning::Diagnostic.state_for(first).asked).to eq(1)
    post answer_diagnostic_path, params: { question_token: flashcard.token, knew: "knew" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Learning::Diagnostic.state_for(first).asked).to eq(1)
  end
end
