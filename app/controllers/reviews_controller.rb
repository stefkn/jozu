class ReviewsController < ApplicationController
  ExposureRecorder = Learning::ExposureRecorder

  def create
    question = Learning::QuestionStore.fetch(review_params[:question_token])
    return render_complete if question.nil?
    return render_idempotent(question) if Review.exists?(question_token: question.token)

    reviewable = question.reviewable_type.constantize.find_by(id: question.reviewable_id)
    return render_complete if reviewable.nil?

    correct = question.correct?(review_params[:answer_id])
    confidence = review_params[:confidence]
    response_time_ms = review_params[:response_time_ms].presence&.to_i
    now = Time.current

    grade = Learning::Scheduler.grade_for(correct:, confidence:, response_time_ms:,
                                          question_type: question.question_type)
    mastery = Learning::MasteryCalculator.update!(reviewable, question_type: question.question_type,
                                                 correct:, confidence:, now:)
    scheduling = Learning::Scheduler.new.apply!(reviewable, grade:, now:)

    ExposureRecorder.record!(user: current_user, kanji: reviewable.kanji, sentence_id: question.sentence_id,
                             kind: "sentence", occurred_at: now) if question.sentence_id
    ExposureRecorder.record!(user: current_user, kanji: reviewable.kanji, kind: "review", occurred_at: now)

    Review.create!(
      user: current_user,
      reviewable:,
      question_type: question.question_type,
      grade:,
      distractors: question.distractors,
      presented_at: question.presented_at,
      answered_at: now,
      correct:,
      response_time_ms:,
      confidence:,
      previous_mastery: mastery.previous_mastery,
      new_mastery: mastery.new_mastery,
      previous_interval: scheduling.previous_interval,
      new_interval: scheduling.new_interval,
      question_token: question.token
    )

    Learning::QuestionStore.delete(question.token)
    render_next(question:)
  end

  private

  def render_next(question:)
    next_question = Learning::NextReview.call(current_user)
    respond_to do |format|
      format.turbo_stream do
        if next_question
          render turbo_stream: turbo_stream.replace("question", partial: "sessions/question",
                                                            locals: { question: next_question })
        else
          render turbo_stream: turbo_stream.replace("question", partial: "sessions/complete",
                                                            locals: { tally: today_tally })
        end
      end
      format.html do
        if next_question
          @question = next_question
          render "sessions/next"
        else
          @tally = today_tally
          render "sessions/complete"
        end
      end
    end
  end

  def render_idempotent(question)
    render_next(question:)
  end

  def render_complete
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("question", partial: "sessions/complete",
                                                  locals: { tally: today_tally })
      end
      format.html do
        @tally = today_tally
        render "sessions/complete"
      end
    end
  end

  def today_tally
    Review.where(user: current_user, created_at: Time.current.all_day)
  end

  def review_params
    params.permit(:question_token, :reviewable_type, :reviewable_id, :answer_id, :confidence, :response_time_ms)
  end
end
