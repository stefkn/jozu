require "rails_helper"

RSpec.describe "Home", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }

  it "renders today's session summary" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Today's session")
    expect(response.body).to include("new kanji")
  end

it "shows a Start button when there is work to do" do
      UserKanji.create!(user:, kanji: Kanji.first)
      get root_path
      expect(response.body).to include("Start")
      expect(response.body).not_to include("Take the diagnostic")
    end

  it "shows an empty state when nothing is due and all kanji are introduced" do
      Kanji.find_each { |k| UserKanji.create!(user:, kanji: k, times_seen: 1) }
      get root_path
      expect(response.body).to include("Nothing due right now")
    end
end
