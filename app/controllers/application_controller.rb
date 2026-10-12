class ApplicationController < ActionController::Base
  before_action :protect_account_response
  before_action :require_user

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  helper_method :current_user

  private

  def require_user
    return if current_user

    if request.get? && request.format.html?
      redirect_to welcome_path
    else
      head :unauthorized
    end
  end

  def protect_account_response
    response.headers["Cache-Control"] = "private, no-store"
    # Keep UUID paths out of referrers without making form POST origins null.
    response.headers["Referrer-Policy"] = "strict-origin"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
