require "rails_helper"

RSpec.describe "Study retirement", type: :request do
  include CorpusHelper

  before { build_corpus!; sign_in(make_user) }

  let(:user) { User.first }

  def leech_kanji(char = "決")
    UserKanji.create!(user:, kanji: k[char], times_seen: 10, times_incorrect: 8,
                      times_correct: 2, mastery_score: 0.3)
  end

  it "suspends a leech, pausing its reviews" do
    uk = leech_kanji
    post suspensions_path, params: { type: "kanji", id: uk.id }
    expect(response).to redirect_to(progress_path)
    expect(uk.reload.suspended_at).to be_present
  end

  it "does not suspend a graduated item" do
    uk = leech_kanji
    uk.update!(graduated_at: Time.current)
    post suspensions_path, params: { type: "kanji", id: uk.id }
    expect(uk.reload.suspended_at).to be_nil
  end

  it "resumes a suspended item" do
    uk = leech_kanji
    uk.update!(suspended_at: Time.current)
    delete suspension_path(uk.id, type: "kanji")
    expect(response).to redirect_to(progress_path)
    expect(uk.reload.suspended_at).to be_nil
  end

  it "resumes a graduated item back into reviews" do
    uk = leech_kanji
    uk.update!(graduated_at: Time.current)
    delete graduation_path(uk.id, type: "kanji")
    expect(response).to redirect_to(progress_path)
    expect(uk.reload.graduated_at).to be_nil
  end

  it "suspends words too" do
    uw = UserWord.create!(user:, word: w["決める"], times_seen: 6,
                         times_incorrect: 5, times_correct: 1, mastery_score: 0.2)
    post suspensions_path, params: { type: "word", id: uw.id }
    expect(uw.reload.suspended_at).to be_present
  end

  it "404s for unknown types and other users' items" do
    uk = leech_kanji
    post suspensions_path, params: { type: "bogus", id: uk.id }
    expect(response).to have_http_status(:not_found)

    other = create(:user)
    other_uk = UserKanji.create!(user: other, kanji: k["定"], times_seen: 6,
                                 times_incorrect: 5, times_correct: 1)
    post suspensions_path, params: { type: "kanji", id: other_uk.id }
    expect(response).to have_http_status(:not_found)
  end

  it "shows leeches and graduated items on the progress page" do
    leech_kanji
    UserKanji.create!(user:, kanji: k["定"], times_seen: 8, times_incorrect: 1,
                      times_correct: 7, mastery_score: 0.9, graduated_at: Time.current)

    get progress_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs attention")
    expect(response.body).to include("Suspend")
    expect(response.body).to include("Graduated")
    expect(response.body).to include("Resume reviews")
  end

  it "shows the due forecast on the home page" do
    uk = UserKanji.create!(user:, kanji: k["決"])
    Learning::Scheduler.new.apply!(uk, grade: :again, now: Time.current - 1.hour)

    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Coming up")
  end
end
