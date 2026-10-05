require "uri"

namespace :jozu do
  desc "Print an existing user's private access link (USER_ID required; APP_URL defaults to localhost)"
  task access_link: :environment do
    user = User.find(ENV.fetch("USER_ID"))
    origin = URI.parse(ENV.fetch("APP_URL", "http://localhost:3000"))
    unless %w[http https].include?(origin.scheme) && origin.host && origin.userinfo.nil? &&
           origin.query.nil? && origin.fragment.nil? && [ "", "/" ].include?(origin.path)
      abort "APP_URL must be an http(s) origin, such as https://jozu.onrender.com"
    end
    puts Rails.application.routes.url_helpers.access_url(
      access_token: user.access_token, host: origin.host, protocol: origin.scheme, port: origin.port
    )
  end
end
