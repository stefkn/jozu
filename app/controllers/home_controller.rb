class HomeController < ApplicationController
  def index
    @summary = Learning::Session.summary(current_user)
    @has_work = @summary.reviews_count.positive? || @summary.new_kanji_count.positive?
    @needs_diagnostic = current_user.user_kanji.empty?
  end
end
