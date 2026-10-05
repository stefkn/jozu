require "rails_helper"

RSpec.describe "Access-link accounts", type: :request do
  include CorpusHelper

  before do
    Rails.cache.clear
    build_corpus!
  end

  it "requires a session and never falls back to an existing user" do
    create(:user)
    get root_path
    expect(response).to redirect_to(welcome_path)
    get welcome_path
    expect(response.body).to include("Create my learning profile")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    post reviews_path, params: { question_token: "missing" }
    expect(response).to have_http_status(:unauthorized)
    patch settings_path, params: { theme: "dark" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get rails_health_check_path
    expect(response).to have_http_status(:ok)
    get pwa_manifest_path(format: :json)
    expect(response).to have_http_status(:ok)
  end

  it "creates a private profile and keeps it signed in" do
    expect { post account_path }.to change(User, :count).by(1)
    expect(response).to redirect_to(account_path)
    follow_redirect!
    expect(response.body).to include(User.last.access_token)
    expect(response.body).to include("Copy link")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect { post account_path }.not_to change(User, :count)
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "restores an existing profile after sign-out without creating another" do
    user = create(:user, settings: { "theme" => "dark" })
    sign_in(user)
    delete account_path
    expect(response).to redirect_to(welcome_path)
    get settings_path
    expect(response).to redirect_to(welcome_path)
    expect { sign_in(user) }.not_to change(User, :count)
    get settings_path
    expect(response.body).to include(user.access_token)
    expect(response.body).to include('data-server-theme="dark"')
  end

  it "keeps the bookmark URL visible without changing accounts until Continue" do
    first = create(:user)
    second = create(:user)
    sign_in(first)
    get access_path(access_token: second.access_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bookmark this page")
    expect(response.body).to include("different profile")
    get account_path
    expect(response.body).to include(first.access_token)
    expect(response.body).not_to include(second.access_token)
    sign_in(second)
    get account_path
    expect(response.body).to include(second.access_token)
    expect(response.body).not_to include(first.access_token)
  end

  it "rejects malformed and unknown links without creating users or switching accounts" do
    user = create(:user)
    sign_in(user)
    [ "invalid", SecureRandom.uuid ].each do |token|
      expect { get access_path(access_token: token) }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found)
      expect { post enter_access_path(access_token: token) }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found)
    end
    get account_path
    expect(response.body).to include(user.access_token)
  end

  it "throttles profile creation" do
    5.times do
      post account_path
      expect(response).to have_http_status(:see_other)
      delete account_path
    end
    expect { post account_path }.not_to change(User, :count)
    expect(response).to have_http_status(:too_many_requests)
  end

  it "requires CSRF tokens to create and enter profiles" do
    original = ActionController::Base.allow_forgery_protection
    begin
      ActionController::Base.allow_forgery_protection = true
      get welcome_path
      expect { post account_path }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      get welcome_path
      csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
      post account_path, params: { authenticity_token: csrf }
      expect(response).to have_http_status(:see_other)
      user = User.last
      post enter_access_path(access_token: user.access_token)
      expect(response).to have_http_status(:unprocessable_content)
      get access_path(access_token: user.access_token)
      csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
      post enter_access_path(access_token: user.access_token), params: { authenticity_token: csrf }
      expect(response).to redirect_to(root_path)
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
  end

  it "redacts access links in request paths and parameters" do
    token = SecureRandom.uuid
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/access/#{token}?access_token=#{token}"))
    request.set_header("action_dispatch.parameter_filter", Rails.application.config.filter_parameters)
    expect(request.filtered_path).not_to include(token)
    expect(request.filtered_path).to include("/access/[FILTERED]")
  end
end
