require "rails_helper"

RSpec.describe "Settings", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  it "renders the settings form" do
    get settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Skip number kanji")
  end

  it "toggles skip_number_kanji" do
    patch settings_path, params: { skip_number_kanji: "1" }
    expect(User.first.reload.skip_number_kanji?).to be true

    patch settings_path, params: { skip_number_kanji: "" }
    expect(User.first.reload.skip_number_kanji?).to be false
  end

  it "toggles practice_mode" do
    patch settings_path, params: { practice_mode: "1" }
    expect(User.first.reload.practice_mode?).to be true

    patch settings_path, params: { practice_mode: "" }
    expect(User.first.reload.practice_mode?).to be false
  end

  it "saves a valid theme and ignores invalid ones" do
    expect(User.first.theme).to eq("system")

    patch settings_path, params: { theme: "dark" }
    expect(User.first.reload.theme).to eq("dark")

    patch settings_path, params: { theme: "bogus" }
    expect(User.first.reload.theme).to eq("dark")
  end

  it "does not reset other settings on theme-only sync" do
    patch settings_path, params: { skip_number_kanji: "1", practice_mode: "1" }
    expect(User.first.reload.skip_number_kanji?).to be true

    patch settings_path, params: { theme: "dark", theme_only: "1" },
          headers: { "Accept" => "application/json" }
    user = User.first.reload
    expect(user.theme).to eq("dark")
    expect(user.skip_number_kanji?).to be true
    expect(user.practice_mode?).to be true
  end

  it "renders the theme picker and header toggle" do
    get settings_path
    expect(response.body).to include("Appearance")
    expect(response.body).to include('name="theme"')

    get root_path
    expect(response.body).to include("Toggle dark mode")
    expect(response.body).to include("data-server-theme")
  end
end
