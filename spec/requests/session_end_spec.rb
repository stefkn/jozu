require "rails_helper"

RSpec.describe "Session end after answering", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  it "completes after the quiz flow (POST-driven) runs out of new kanji" do
    get next_sessions_path
    token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    expect(token).not_to be_nil

    answered = 0
    10.times do
      question = Learning::QuestionStore.fetch(token)
      expect(question).not_to be_nil

      post reviews_path, params: {
        question_token: token,
        reviewable_type: question.reviewable_type,
        reviewable_id: question.reviewable_id,
        answer_id: question.correct_option_id,
        confidence: "knew",
        response_time_ms: "900"
      }, as: :turbo_stream

      answered += 1
      token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
      break if token.nil?
    end

    expect(answered).to eq(3)
    expect(Review.count).to eq(3)
    expect(response.body).to include("Session complete")
  end
end
