class KnownnessController < ApplicationController
  # Explicit spoken-word labeling from the quiz ("Do you say this word?").
  # Creates/updates the UserWord mastery without touching SRS or reviews.
  def create
    word = Word.find_by(id: params[:word_id])
    return render json: { ok: false, error: "unknown word" }, status: :not_found if word.nil?

    begin
      record = Learning::WordKnownness.mark!(current_user, word:, level: params[:level])
    rescue ArgumentError
      return render json: { ok: false, error: "unknown level" }, status: :unprocessable_content
    end

    respond_to do |format|
      format.json { render json: { ok: true, mastery: record.mastery_score } }
      format.html { redirect_back fallback_location: root_path }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "knownness-#{word.id}",
          partial: "sessions/knownness_saved",
          locals: { word: }
        )
      end
    end
  end
end
