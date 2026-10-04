require "rails_helper"

RSpec.describe "Reading", type: :request do
  include CorpusHelper

  before { build_corpus!; make_user }

  let(:user) { User.first }

  it "shows a short reading passage" do
    get reading_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Short reading")
    expect(response.body).to include("I read this")
  end

  it "completing a passage records exposures and bumps context" do
    uk = UserKanji.create!(user:, kanji: Kanji.find_by(character: "決"),
                           context_strength: 0.1, recognition_strength: 0.5,
                           reading_strength: 0.5, mastery_score: 0.4)
    sentence = Sentence.find_by(japanese: "明日までに決めます。")

    expect do
      post complete_reading_path, params: { sentence_ids: [ sentence.id ] }
    end.to change { Exposure.where(user:, kind: "reading").count }.by_at_least(1)

    expect(response).to redirect_to(root_path)
    expect(uk.reload.context_strength).to be > 0.1
  end

  it "home shows a short reading when passages are available" do
    UserKanji.create!(user:, kanji: Kanji.first)
    get root_path
    expect(response.body).to include("Short reading")
  end
end
