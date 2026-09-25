class SettingsController < ApplicationController
  def show
  end

  def update
    # Header dark-mode toggle syncs theme-only (fetch with theme_only=1) so it
    # must not reset the other checkboxes, which are absent outside the form.
    unless params[:theme_only].present?
      current_user.set_setting("skip_number_kanji", params[:skip_number_kanji].present?)
      current_user.set_setting("practice_mode", params[:practice_mode].present?)
    end
    if params[:theme].present? && User::THEMES.include?(params[:theme])
      current_user.set_setting("theme", params[:theme])
    end
    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Settings saved." }
      format.json { render json: { ok: true, theme: current_user.theme } }
    end
  end
end
