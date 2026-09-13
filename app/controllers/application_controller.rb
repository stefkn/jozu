class ApplicationController < ActionController::Base
  # Plan A: single seeded demo user, no auth.
  def current_user
    @current_user ||= User.first
  end
  helper_method :current_user
end
