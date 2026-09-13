class SessionsController < ApplicationController
  def next_question
    @question = Learning::NextReview.call(current_user)
    if @question
      render "sessions/next"
    else
      @tally = today_tally
      render "sessions/complete"
    end
  end

  def complete
    @tally = today_tally
    render "sessions/complete"
  end

  private

  def today_tally
    Review.where(user: current_user, created_at: Time.current.all_day)
  end
end
