require "rails_helper"

RSpec.describe "Quiz flow", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }

  it "runs a full question -> answer -> next loop" do
    get next_sessions_path
    expect(response).to have_http_status(:ok)

    body = response.body
    token = body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    expect(token).not_to be_nil

    question = Learning::QuestionStore.fetch(token)
    correct_answer = question.correct_option_id

    expect do
      post reviews_path, params: {
        question_token: token,
        reviewable_type: question.reviewable_type,
        reviewable_id: question.reviewable_id,
        answer_id: correct_answer,
        confidence: "knew",
        response_time_ms: "900"
      }, as: :turbo_stream
    end.to change(Review, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("turbo-stream")
    review = Review.last
    expect(review.correct).to be true
    expect(review.grade).to eq("good")
    expect(review.question_token).to eq(token)
    expect(review.distractors).to eq(question.distractors)
  end

  it "records the mastery update on the review row" do
    get next_sessions_path
    token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    question = Learning::QuestionStore.fetch(token)

    post reviews_path, params: {
      question_token: token,
      reviewable_type: question.reviewable_type,
      reviewable_id: question.reviewable_id,
      answer_id: question.correct_option_id,
      confidence: "unknown",
      response_time_ms: "500"
    }, as: :turbo_stream

    review = Review.last
    expect(review.grade).to eq("again")
    expect(review.new_mastery).to be > review.previous_mastery
  end

  it "is idempotent for a double-submitted token" do
    get next_sessions_path
    token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    question = Learning::QuestionStore.fetch(token)

    params = {
      question_token: token,
      reviewable_type: question.reviewable_type,
      reviewable_id: question.reviewable_id,
      answer_id: question.correct_option_id,
      confidence: "knew",
      response_time_ms: "900"
    }

    expect do
      post reviews_path, params:, as: :turbo_stream
      post reviews_path, params:, as: :turbo_stream
    end.to change(Review, :count).by(1)
  end

  it "rejects a tampered answer" do
    get next_sessions_path
    token = response.body[/name="question_token"[^>]*value="([^"]+)"/, 1]
    question = Learning::QuestionStore.fetch(token)
    wrong_answer = question.options.keys.find { |id| id != question.correct_option_id }
    expect(wrong_answer).not_to be_nil

    post reviews_path, params: {
      question_token: token,
      reviewable_type: question.reviewable_type,
      reviewable_id: question.reviewable_id,
      answer_id: wrong_answer,
      confidence: "knew",
      response_time_ms: "900"
    }, as: :turbo_stream

    review = Review.last
    expect(review.correct).to be false
    expect(review.grade).to eq("again")
  end

  it "serves the session-complete card when the session ends" do
    3.times { Learning::NextReview.call(user) }
    get next_sessions_path
    expect(response.body).to include("Session complete")
  end
end
