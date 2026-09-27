class SuspensionsController < ApplicationController
  # Manual "stop drilling this" button for leeches. Suspended items keep their
  # rows and mastery (so Progress still shows them) but never come due until
  # resumed. Graduated items cannot be suspended — they are already out.
  def create
    record = study_item
    record.update!(suspended_at: Time.current) unless record.graduated_at.present?
    redirect_back fallback_location: progress_path
  end

  def destroy
    record = study_item
    record.update!(suspended_at: nil)
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
