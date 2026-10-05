class AccountsController < ApplicationController
  skip_before_action :require_user, only: %i[new create access enter]
  rate_limit to: 5, within: 1.hour, only: :create,
             with: -> { render plain: "Too many profiles created. Please try again later.", status: :too_many_requests }

  def new
    redirect_to root_path if current_user
  end

  def create
    return redirect_to account_path if current_user

    sign_in(User.create!)
    redirect_to account_path, status: :see_other
  end

  def access
    @access_user = user_from_link
    render :invalid, status: :not_found unless @access_user
  end

  def enter
    user = user_from_link
    return render :invalid, status: :not_found unless user

    sign_in(user)
    redirect_to root_path, status: :see_other
  end

  def show
  end

  def destroy
    reset_session
    redirect_to welcome_path, status: :see_other
  end

  private

  def user_from_link
    token = params[:access_token].to_s
    return unless token.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)

    User.find_by(access_token: token)
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end
end
