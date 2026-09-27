class GraduationsController < ApplicationController
  # Resume reviews for a graduated item: clears the flag so it rejoins the due
  # queue on its stored FSRS card (no reset — the scheduling history is kept).
  def destroy
    record = study_item
    record.update!(graduated_at: nil)
    redirect_back fallback_location: progress_path
  end

  private

  def study_item
    case params[:type].to_s
    when "kanji" then current_user.user_kanji.find(params[:id])
    when "word" then current_user.user_words.find(params[:id])
    else raise ActiveRecord::RecordNotFound
    end
  end
end
