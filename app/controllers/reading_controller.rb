class ReadingController < ApplicationController
  def show
    @passages = Learning::ReadingPassage.select(current_user)
  end

  def complete
    sentences = Sentence.where(id: Array(params[:sentence_ids]).map(&:to_i))
    if sentences.any?
      Learning::ReadingFeedback.record!(user: current_user, sentences:)
      redirect_to root_path, notice: "Reading saved — stable kanji keep reinforcing through reading."
    else
      redirect_to reading_path, alert: "Nothing to save."
    end
  end
end
