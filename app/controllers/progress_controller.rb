class ProgressController < ApplicationController
  def index
    @progress = Learning::Progress.call(current_user)
    @leeches = Learning::Leeches.call(current_user)
    @graduated = Learning::Leeches.graduated(current_user)
  end

  def show
    kanji = Kanji.includes(:readings, :words).find_by(character: params[:character])
    raise ActiveRecord::RecordNotFound if kanji.nil?

    @kanji = kanji
    @detail = Learning::OptionDetails.for_kanji(kanji)
    @mastery = current_user&.user_kanji&.find_by(kanji: kanji)
  end
end
