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
end
