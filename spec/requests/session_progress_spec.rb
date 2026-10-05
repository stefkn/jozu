require "rails_helper"

RSpec.describe "Session progress", type: :request do
  include CorpusHelper

  before { build_corpus!; sign_in(make_user) }

  let(:user) { User.first }

  it "shows a progress bar on the question page" do
    uk = UserKanji.create!(user:, kanji: k["決"])
    Learning::Scheduler.new.apply!(uk, grade: :again, now: Time.current - 1.hour)

    get next_sessions_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('role="progressbar"')
    # 1 due + 2 new-kanji slots (one slot already used by today's row).
    expect(response.body).to include("0 of 3 today")
  end

  it "ends the session at the daily target with a full bar" do
    uk = UserKanji.create!(user:, kanji: k["決"])
    10.times do
      Review.create!(user:, reviewable: uk, question_type: "kana_to_kanji", grade: "good",
                     presented_at: Time.current, answered_at: Time.current, correct: true)
    end

    get next_sessions_path
    expect(response.body).to include("Session complete")
    expect(response.body).to include("10 of 10 today")
  end
end
