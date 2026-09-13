class DiagnosticController < ApplicationController
  def show
    @flashcard = Learning::Diagnostic.start(current_user)
    render "diagnostic/show"
  end

  def answer
    item = Learning::QuestionStore.fetch(params[:question_token])
    if item.nil? || !item.is_a?(Learning::Flashcard)
      @flashcard = nil
      render_quiz
      return
    end

    word = Word.find_by(id: item.word_id)
    if word.nil?
      @flashcard = nil
      render_quiz
      return
    end

    correct, confidence = map_self_assessment(params[:knew])
    @flashcard = Learning::Diagnostic.answer(current_user, word_id: word.id, correct:,
                                                            confidence:)
    render_quiz
  end

  private

  # Flashcard self-assessment -> (correct, confidence) for the diagnostic engine.
  def map_self_assessment(knew)
    case knew
    when "knew" then [ true, "knew" ]
    when "guessed" then [ false, "guessed" ]
    else [ false, "unknown" ]
    end
  end

  def render_quiz
    respond_to do |format|
      format.turbo_stream do
        if @flashcard
          render turbo_stream: turbo_stream.replace("question", partial: "diagnostic/flashcard",
                                                            locals: { flashcard: @flashcard })
        else
          render turbo_stream: turbo_stream.replace("question", partial: "diagnostic/done")
        end
      end
      format.html { render "diagnostic/show" }
    end
  end
end
