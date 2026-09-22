class SettingsController < ApplicationController
  def show
  end

  def update
    current_user.set_setting("skip_number_kanji", params[:skip_number_kanji].present?)
    current_user.set_setting("practice_mode", params[:practice_mode].present?)
    redirect_to settings_path, notice: "Settings saved."
  end
end
