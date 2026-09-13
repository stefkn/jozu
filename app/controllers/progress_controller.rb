class ProgressController < ApplicationController
  def index
    @progress = Learning::Progress.call(current_user)
  end
end
