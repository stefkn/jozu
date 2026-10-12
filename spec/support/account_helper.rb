module AccountHelper
  def sign_in(user)
    post enter_access_path(access_token: user.access_token)
  end
end

RSpec.configure do |config|
  config.include AccountHelper, type: :request
end
